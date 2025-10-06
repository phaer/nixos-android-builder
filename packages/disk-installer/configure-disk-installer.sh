#!/usr/bin/env bash
# Given a disk image or block device, find its ESP partition,
# and write a device path to the file "install_target" inside
# it. That file will be read at run-time, if it exists.
# If it does, we'll copy our disk image to the target disk
# in early boot, before rebooting.
set -euo pipefail

usage() {
    cat << EOF
Usage: $0 <device> <install-target>

Configure the disk-installer on <device>, which can be either a block device or
a disk image, to install to <install-target> upon boot.
<install-target> can be:

- a device path on the target machine.
- "select" to start an interactive menu upon boot.
- "none" to skip the installer an just boot the image directly.

<install_target> is then written to /boot/install_target where it will be picked
up by the installer.
If <install_target> is empty, the current one will be listed.
EOF
    exit 1
}
[ $# -eq 0 ] && usage

installer_device="$1"
install_target="${2:-}"

if [ -b "$installer_device" ] && [ $UID != 0 ]; then
    echo "Target is a block device, but we are not root. Running sudo"
    exec sudo "$0" "$@"
fi

echo >&2 "Searching ESP partition offset in $installer_device"
esp_offset="$(
  parted \
    --script \
    --json \
    "$installer_device" \
    -- unit B print \
    | \
 jq -r '
   .disk.partitions[]
   | select(.flags and (.flags | contains(["esp"])))
   | .start
   | rtrimstr("B")'
)"

mtools_args="-v -i $installer_device@@$esp_offset"
mcopy_args="$mtools_args -o"

if [ -z "$install_target" ]; then
    if ! install_target="$(mtype $mtools_args ::install_target 2> /dev/null)"; then
        install_target="none"
        echo >&2 "$installer_device will not run the installer"
    else
        if [ "$install_target" = "select" ]; then
            echo >&2 "$installer_device will offer an interactive menu"
        else
            echo >&2 "$installer_device will install to $install_target"
        fi
    fi
else
    if [ "$install_target" = "none" ]; then
        echo >&2 "Deactivating installer in $installer_device"
        mdel $mtools_args ::install_target 2> /dev/null || true
        echo >&2 "Done. Image will boot without running the installer"
    else
        echo >&2 "Configuring installer in $installer_device"
        temp_file=$(mktemp --suffix "install_target")
        cleanup() {
            rm "$temp_file"
        }
        trap "cleanup" EXIT
        echo "$install_target" > "$temp_file"

        mcopy $mcopy_args "$temp_file" "::install_target"

        if [ "$install_target" = "select" ]; then
            echo >&2 "Done. Image will offer an interactive menu for the installer upon boot."
        else
            echo >&2 "Done. Image will be copied to $install_target upon boot."
        fi
    fi
fi
