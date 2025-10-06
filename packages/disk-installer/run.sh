set -euo pipefail

ddrescue2gauge() {
    local total="$1"
    local pct="0"
    local copied="0 B"
    local rate="0 B/s"
    local remaining="unknown"
    local errors="0"

    while IFS= read -r line; do
        if [[ "$line" =~ pct\ rescued:[[:space:]]*([0-9.]+)% ]]; then
            pct="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ rescued:[[:space:]]*([0-9.]+[[:space:]]*[kMGT]?B) ]]; then
            copied="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ current\ rate:[[:space:]]*([0-9.]+[[:space:]]*[kMGT]?B/s) ]]; then
            rate="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ remaining\ time:[[:space:]]*([^,[:space:]]+) ]]; then
            remaining="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ read\ errors:[[:space:]]*([0-9]+) ]]; then
            errors="${BASH_REMATCH[1]}"
        fi

        if [[ "$line" =~ time\ since\ last\ successful\ read ]]; then
            pct_int=${pct%.*}
            echo "$pct_int"
            echo "XXX"
            echo "Copied: ${copied} of ${total}"
            echo "Rate: ${rate}"
            echo "Estimated Time Remaining: ${remaining}"
            echo "Errors: ${errors}"
            echo "XXX"
        fi
    done
}

select_disk() {
    if ! disk_json="$(lsblk --json --nodeps --output NAME,SIZE,TYPE,MODEL 2>/dev/null)"; then
        echo "Error: Failed to retrieve disk information"
        exit 1
    fi

    menu_options=()
    while IFS='|' read -r name size model; do
        device="/dev/$name"
        if [ "$device" = "$1" ]; then
            continue
        fi
        description="$size   (${model:-Unknown model})"
        menu_options+=("$device" "$description")
    done < <(echo "$disk_json" | jq -r '.blockdevices[] | select(.type == "disk") | "\(.name)|\(.size)|\(.model // "Unknown")"')

    if [ ${#menu_options[@]} -eq 0 ]; then
        echo "Error: No disks found"
        exit 1
    fi

    selected_disk="$(
    dialog 3>&1 1>&2 2>&3 \
        --colors \
        --title "Disk Selection" \
        --nocancel \
        --menu "Select a disk to install to. All existing data on it will be WIPED!" \
        20 60 10 \
        "${menu_options[@]}"
    )"

    echo "$selected_disk"
}

exec 4> >(systemd-cat -p info)
exec 5> >(systemd-cat -p err)

echo -e "\nDisk Installer\n" >&4



if [ ! -f /boot/install_target ]; then
  echo "/boot/install_target not found." >&5
  exit 0
fi

if [ ! -t 1 ]; then
    echo "stdout is NOT a tty" >&5
    exit 1
fi

install_source="$(
  lsblk --json --output NAME,MOUNTPOINT,PKNAME | jq -r '
    .. | objects | select(.mountpoint=="/boot") |
    "/dev/\(if .pkname then .pkname else .name end)"
  '
)"
install_source_size="$(lsblk --raw --noheadings --nodeps --output SIZE "$install_source")"
if [ ! -b "$install_source" ]; then
  echo "ERROR: installation source \"$install_source\" is not a block device." >&5
  exit 1
fi

install_target="$(cat /boot/install_target)"
if [ "$install_target" = "select" ]; then
    install_target="$(select_disk "$install_source")"
fi

if [ ! -b "$install_target" ]; then
  echo "ERROR: installation target \"$install_target\" is not a block device." >&5
  exit 1
fi

intro_msg="About to install from $install_source to $install_target"
echo  "$intro_msg" >&4
if ! dialog --colors --pause "$intro_msg" 10 40 3; then
    echo "User cancelled installation." >&4
    exit
fi

echo "removing /boot/install_target" >&4
rm /boot/install_target

echo "unmounting /boot before copying" >&4
systemctl stop boot.mount

echo "ensuring that $install_target >= $install_source." >&4
if ! out=$(lsblk --bytes --json "$install_source" "$install_target" \
  | jq -e --arg src "${install_source#/dev/}" --arg tgt "${install_target#/dev/}" '
    .blockdevices
    | map({(.name): .size})
    | add
    | {src: (.[ $src ]/1024/1024/1024 | round),
       tgt: (.[ $tgt ]/1024/1024/1024 | round)}
    | if .tgt >= .src then
        "Target disk is big enough: \($tgt) (\(.tgt) GB) >= \($src) (\(.src) GB)"
      else
        error("\($tgt) (\(.tgt) GB) < \($src) (\(.src) GB)")
      end
  ' 2>&1); then
  echo "ERROR: $install_target too small: $out" >&5
  exit 1
else
  echo "$out" >&4
fi

msg_copy="Copying source disk $install_source to target disk $install_target"
echo $msg_copy >&4
ddrescue -f -v "$install_source" "$install_target" 2>&1 \
    | ddrescue2gauge "$install_source_size" \
    | dialog --colors --title "$msg_copy" --gauge "Starting..." 16 60 10


printf "fix\n" | parted ---pretend-input-tty "$install_target" print
sync

echo 1 > /run/installer_done  # marker file for automated tests

msg_done="Installation to $install_target done.\n\nPlease remove the installation media before pressing enter to reboot."
echo "$msg_done" >&4
dialog --colors --ok-button " Reboot " --msgbox "$msg_done" 10 60

systemctl reboot
