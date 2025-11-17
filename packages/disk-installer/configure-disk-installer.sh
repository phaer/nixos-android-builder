#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")

usage() {
    cat << EOF
Usage: $SCRIPT_NAME <command> [arguments]

Commands:
    status <device>                Check status of installer image
    sign <keystore> <device>       Sign bootloader for Secure Boot
    install [target] <device>      Configure installation target

Arguments:
    device     Block device or disk image file
    keystore   Directory containing db.key and db.crt
    target     Target device for automatic installation (e.g., /dev/sda)

Examples:
    $SCRIPT_NAME status installer.raw
    $SCRIPT_NAME sign ./keystore installer.raw
    $SCRIPT_NAME install installer.raw
    $SCRIPT_NAME install /dev/sda installer.raw
EOF
    exit 1
}

die() {
    echo "Error: $*" >&2
    exit 1
}

get_partition_offset() {
    local device="$1"
    local type_uuid="$2"
    local layout start sector
    layout="$(sfdisk -J "$device" 2>/dev/null)"
    start=$(echo "$layout" | jq -r "
        .partitiontable.partitions[] |
        select(.type == \"$type_uuid\") |
        .start
    ") || die "Cannot read partition table"
    [[ -z "$start" ]] && die "Cannot find partition of type $type_uuid"
    sector=$(echo "$layout" | jq -r '.partitiontable.sectorsize // 512')
    echo $((start * sector))
}

get_inner_esp_offset() {
    local device="$1"
    local outer_offset inner_start
    # Find the nested partition (type 0FC63DAF-8483-4772-8E79-3D69D8477DE4)
    outer_offset=$(get_partition_offset "$device" "0FC63DAF-8483-4772-8E79-3D69D8477DE4")
    # Parse GPT partition entries at LBA 2, starting at byte 32 of first entry
    local gpt_entry_offset=$((outer_offset + 1024 + 32))
    inner_start=$(dd if="$device" bs=1 skip=$gpt_entry_offset count=8 2>/dev/null | od -An -t u8 -N 8 | tr -d ' ')
    [[ -z "$inner_start" ]] && die "Cannot parse GPT partition table"
    echo $((outer_offset + inner_start * 512))
}

get_outer_esp_offset() {
    local device="$1"
    # Find the EFI System Partition (type C12A7328-F81F-11D2-BA4B-00A0C93EC93B or "EFI System")
    echo $(get_partition_offset "$device" "C12A7328-F81F-11D2-BA4B-00A0C93EC93B")
}

cmd_status() {
    local device="${1:-}"
    [[ -n "$device" ]] || die "status command requires <device> argument"
    [[ -e "$device" ]] || die "Device or image file not found: $device"

    local outer_esp_offset=$(get_outer_esp_offset "$device")
    local outer_img_spec="${device}@@${outer_esp_offset}"
    mdir -i "$outer_img_spec" :: >/dev/null 2>&1 || die "Cannot access EFI partition (invalid FAT filesystem)"
    local inner_esp_offset=$(get_inner_esp_offset "$device")
    local inner_img_spec="${device}@@${inner_esp_offset}"
    mdir -i "$inner_img_spec" :: >/dev/null 2>&1 || die "Cannot access nested EFI partition (invalid FAT filesystem)"

    echo "Installation target:"
    if mdir -i "$outer_img_spec" ::/install_target >/dev/null 2>&1; then
        local target=$(mtype -i "$outer_img_spec" ::/install_target 2>/dev/null | tr -d '\r\n')
        echo "  Automatic installation to: $target"
    else
        echo "  Interactive menu (user will select target)"
    fi
    echo ""

    echo "Payload Secure Boot signatures:"
    local temp_efi=$(mktemp --suffix=".efi")
    trap "rm -f '$temp_efi'" EXIT
    mcopy -n -i "$inner_img_spec" ::/EFI/BOOT/BOOTX64.EFI "$temp_efi"
    sbverify --list "$temp_efi"
}

cmd_sign() {
    local keystore="${1:-}"
    local device="${2:-}"
    [[ -n "$keystore" && -n "$device" ]] || die "sign command requires <keystore> and <device> arguments"
    [[ -e "$device" ]] || die "Device or image file not found: $device"
    [[ -d "$keystore" ]] || die "Keystore directory not found: $keystore"
    [[ -f "$keystore/db.key" && -f "$keystore/db.crt" ]] || die "Missing db.key or db.crt in keystore"

    local inner_esp_offset=$(get_inner_esp_offset "$device")
    local inner_img_spec="${device}@@${inner_esp_offset}"
    mdir -i "$inner_img_spec" :: >/dev/null 2>&1 || die "Cannot access EFI partition (invalid FAT filesystem)"

    local temp_efi=$(mktemp --suffix=".efi")
    trap "rm -f '$temp_efi'" EXIT

    echo "Extracting bootloader..."
    mcopy -n -i "$inner_img_spec" ::/EFI/BOOT/BOOTX64.EFI "$temp_efi" 2>/dev/null || die "Failed to extract bootloader"

    echo "Signing with Secure Boot key..."
    sbsign --key "$keystore/db.key" --cert "$keystore/db.crt" --output "$temp_efi" "$temp_efi" || die "Failed to sign bootloader"

    echo "Writing signed bootloader back..."
    mcopy -n -o -i "$inner_img_spec" "$temp_efi" ::/EFI/BOOT/BOOTX64.EFI 2>/dev/null || die "Failed to write bootloader"

    echo "✓ Bootloader signed successfully"
}

cmd_install() {
    local target=""
    local device=""

    case $# in
        1) device="$1" ;;
        2) target="$1"; device="$2" ;;
        *) die "install command requires <device> and optional [target] argument" ;;
    esac

    [[ -e "$device" ]] || die "Device or image file not found: $device"

    local outer_esp_offset=$(get_outer_esp_offset "$device")
    local outer_img_spec="${device}@@${outer_esp_offset}"
    mdir -i "$outer_img_spec" :: >/dev/null 2>&1 || die "Cannot access EFI partition (invalid FAT filesystem)"

    if [[ -z "$target" ]]; then
        mdel -i "$outer_img_spec" ::/install_target 2>/dev/null || true
        echo "✓ Configured for interactive installation"
        echo "  User will select target disk during boot"
    else
        local temp_target=$(mktemp)
        trap "rm -f '$temp_target'" EXIT
        echo -n "$target" > "$temp_target"
        mcopy -n -o -i "$outer_img_spec" "$temp_target" ::/install_target 2>/dev/null || die "Failed to write install target"
        echo "✓ Configured for automatic installation"
        echo "  Will install to: $target"
    fi
}

[[ $# -eq 0 ]] && usage

command="$1"
shift

case "$command" in
    status)  cmd_status "$@" ;;
    sign)    cmd_sign "$@" ;;
    install) cmd_install "$@" ;;
    -h|--help|help) usage ;;
    *) die "Unknown command: $command" ;;
esac
