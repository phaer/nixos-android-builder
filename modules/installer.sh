set -euo pipefail

ddrescue2gauge() {
    local pct="0"
    local copied="0 B"
    local rate="0 B/s"
    local remaining="unknown"
    local errors="0"

    while IFS= read -r line; do
        if [[ "$line" =~ pct\ rescued:[[:space:]]*([0-9.]+)% ]]; then
            pct="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ rescued:[[:space:]]*([^,]+) ]]; then
            copied="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ current\ rate:[[:space:]]*([^[:space:]]+) ]]; then
            rate="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ remaining\ time:[[:space:]]*([^[:space:]]+) ]]; then
            remaining="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ read\ errors:[[:space:]]*([0-9]+) ]]; then
            errors="${BASH_REMATCH[1]}"
        fi

        # When we hit a complete status block, output to gauge
        if [[ "$line" =~ time\ since\ last\ successful\ read ]]; then
            pct_int=${pct%.*}
            echo "$pct_int"
            echo "XXX"
            echo "Copied: ${copied} (${pct}%)"
            echo "Rate: ${rate} | Remaining: ${remaining}"
            echo "Errors: ${errors}"
            echo "XXX"
        fi
    done
}

grab_console() {
    exec 3>&1 # save original stdout in fd 3
    exec > >(tee /dev/console) 2>&1 # duplicate stdout&err to console+journal.
}

restore_console() {
    exec 1>&3 2>&1 # restore stdout/stderr
    exec 3>&- # close fd 3
}

select_disk() {
    disk_json="$(lsblk -J -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null)"
    if [ $? -ne 0 ]; then
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
    dialog \
        --title "Disk Selection" \
        --menu "Select a disk to install to. All existing data will be WIPED!" \
        --nocancel \
        20 60 10 \
        "${menu_options[@]}" \
        3>&1 1>&2 2>&3)"

    echo "$selected_disk"
}

grab_console

echo -e "\nDisk Installer\n"

if [ -t 1 ]; then
    echo "stdout is a tty"
else
    echo "stdout is NOT a tty"
fi

if [ ! -f /boot/install_target ]; then
  echo "/boot/install_target not found."
  exit 0
fi

install_source="$(
  lsblk -J -o NAME,MOUNTPOINT,PKNAME | jq -r '
    .. | objects | select(.mountpoint=="/boot") |
    "/dev/\(if .pkname then .pkname else .name end)"
  '
)"
if [ ! -b "$install_source" ]; then
  echo "ERROR: installation source \"$install_source\" is not a block device."
  exit 1
fi

install_target="$(cat /boot/install_target)"
if [ "$install_target" = "select" ]; then
    install_target="$(select_disk "$install_source")"
fi

if [ ! -b "$install_target" ]; then
  echo "ERROR: installation target \"$install_target\" is not a block device."
  exit 1
fi

echo "removing /boot/install_target"
rm /boot/install_target

echo "unmounting /boot before copying"
systemctl stop boot.mount

echo "ensuring that $install_target >= $install_source."
if ! out=$(lsblk -b -J "$install_source" "$install_target" \
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
  echo "ERROR: $install_target too small: $out"
  exit 1
else
  echo "$out"
fi

echo "Copying source disk \"$install_source\" to target disk \"$install_target\"."
ddrescue -f -v "$install_source" "$install_target" 2>&1 \
    | ddrescue2gauge \
    | dialog --gauge "Copying $install_source to $install_target" 16 60 10


printf "fix\n" | parted ---pretend-input-tty "$install_target" print
sync

echo 1 > /run/installer_done  # marker file for automated tests

dialog  --msgbox "Installation to $install_target done.\n\nPlease remove the installation media before pressing enter to reboot." 10 60 --ok-button " Reboot "

restore_console
systemctl reboot
