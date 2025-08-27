#!/usr/bin/env bash
# Given a disk image, mount it's ESP partition via qemu-nbd,
# and sign the default EFI application on it.
# Uses qemu-nbd instead of losetup, because that can handle
# both, raw disk images, as well as qcow2 images. The backing
# layer stays read-only in /nix/store while we modify the
# COW layer in the latter case.
# It assumes secure boot keys to exist in $keystore, the
# $nbd_device to be free, as well as the ESP to be found on
# partition number $disk_image_partition.
set -euo pipefail

keystore="keys"
disk_image_file="$1"
disk_image_partition="${2:-1}"
disk_image_format="$(qemu-img info "$disk_image_file" | awk '/^file format/ {print $3}')"

nbd_device="/dev/nbd0"
nbd_partition="/dev/mapper/$(basename "$nbd_device")p${disk_image_partition}"

esp_uki="EFI/BOOT/BOOTX64.EFI"
esp_keystore="EFI/KEYS"

declare -a CLEANUP_STACK
on_cleanup() {
    CLEANUP_STACK+=("$1")
    # Update the trap to run all items in stack (in reverse order)
    local cleanup_cmd=""
    local i
    for ((i=${#CLEANUP_STACK[@]}-1; i>=0; i--)); do
        if [ -n "$cleanup_cmd" ]; then
            cleanup_cmd="$cleanup_cmd; "
        fi
        cleanup_cmd="$cleanup_cmd${CLEANUP_STACK[i]}"
    done
    trap "$cleanup_cmd" EXIT
}
on_cleanup 'echo >&2 "Done. $disk_image_file includes a signed UKI & keys for enrollment now."'
on_cleanup 'sleep 1; udevadm settle -t 5'


echo >&2 "Loading nbd kernel module"
if ! lsmod | grep -q nbd; then
    sudo modprobe nbd
fi
on_cleanup 'sudo modprobe nbd'

echo >&2 "Attaching $disk_image_format image $disk_image_file to $nbd_device"
sudo qemu-nbd \
     --format="$disk_image_format" \
     --connect="$nbd_device" \
     "$disk_image_file"
on_cleanup 'sudo qemu-nbd --disconnect "$nbd_device"'

echo >&2 "Scanning for partitions in $nbd_device"
sudo kpartx -a "$nbd_device"
on_cleanup 'sudo kpartx -d "$nbd_device"'

mount_point=$(mktemp -d)
on_cleanup 'rm -rf "$mount_point"'

echo >&2 "Mounting $nbd_partition to $mount_point"
sudo mount "$nbd_partition" "$mount_point"
on_cleanup 'sudo umount "$mount_point"'

echo >&2 "Signing $mount_point/$esp_uki"
sudo sbsign \
     --key keys/db.key \
     --cert keys/db.crt \
     "$mount_point/$esp_uki" \
     --output "$mount_point/$esp_uki"

echo >&2 "Copying certificates from $keystore to $mount_point/$esp_keystore"
sudo mkdir -p "$mount_point/$esp_keystore"
sudo cp -v "$keystore"/{PK,KEK,db}.auth "$mount_point/$esp_keystore"
