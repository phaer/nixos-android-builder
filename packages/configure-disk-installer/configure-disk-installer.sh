#!/usr/bin/env bash
# Given a disk image, find its ESP partition, and
# write a device path to the file "install_target" inside
# it. That file will be read at run-time, if it exists.
# If it does, we'll copy our disk image to the target disk
# in early boot, before rebooting.
set -euo pipefail

target_image_file="$1"
target_install_disk="$2"

temp_file=$(mktemp --suffix "install_target")


cleanup() {
    rm "$temp_file"
}
trap "cleanup" EXIT

echo >&2 "Searching ESP partition offset in $target_image_file"
esp_offset="$(
  parted \
    --script \
    --json \
    "$target_image_file" \
    -- unit B print \
    | \
 jq -r '
   .disk.partitions[]
   | select(.flags and (.flags | contains(["esp"])))
   | .start
   | rtrimstr("B")'
)"

mtools_args="-i $target_image_file@@$esp_offset"
mcopy_args="$mtools_args -o"

echo >&2 "Writing $target_install_disk to install_target"

echo "$target_install_disk" > "$temp_file"

mcopy $mcopy_args "$temp_file" "::install_target"

echo >&2 "Done. Image will be copied to $target_install_disk on first boot."
