#!/usr/bin/env bash

set -e

if [ ! -d keys ]; then
	echo "Directory 'keys' doesn't exist! Please create signing keys first."
	exit 1
fi

TMPDIR=$(mktemp -d)

# copy the image out of the nix store, or it will be read-only
cp -L result/*.raw "$TMPDIR"

cleanup() {
	sudo umount /mnt
	sudo losetup -d "$loopdev"
}

trap cleanup EXIT

loopdev=$(sudo losetup -f)
sudo losetup -P "$loopdev" "$TMPDIR"/*.raw
sudo mount "${loopdev}p1" /mnt -t vfat

sudo find /mnt/ -iname "*.efi" -type f -exec sbsign --key keys/db.key --cert keys/db.crt --output {} {} \;

KEYSTORE="/EFI/keys/"
sudo mkdir -p /mnt${KEYSTORE}

echo "Copying keys to ${KEYSTORE}"
sudo cp keys/*.crt /mnt${KEYSTORE}
sudo cp keys/*.cer /mnt${KEYSTORE}
sudo cp keys/*.auth /mnt${KEYSTORE}

IMAGE=$(find "$TMPDIR" -iname "*.raw" -type f)
echo "You can now flash the signed image like so:"
echo "sudo dd status=progress bs=128M if=${IMAGE} of=YOURDISKHERE"
