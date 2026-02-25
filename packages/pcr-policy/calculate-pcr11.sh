#!/usr/bin/env bash
#
# Calculate the expected PCR 11 value for a UKI image.
#
# systemd-stub measures each PE section of the UKI into PCR 11, then
# systemd-pcrphase extends it with boot phase strings.  This script
# reproduces that calculation offline using systemd-measure so that
# the expected value can be fed into a keylime TPM policy.
#
# Usage: calculate-pcr11 <path-to-uki.efi>
#
# Outputs the sha256 PCR 11 hash to stdout (64 hex characters, no newline).

set -euo pipefail

uki="${1:?Usage: calculate-pcr11 <path-to-uki.efi>}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

cp "$uki" uki.efi
chmod 644 uki.efi

for section in .linux .osrel .cmdline .initrd .uname .sbat; do
	name="${section#.}"
	objcopy --dump-section "${section}=${name}" uki.efi 2>/dev/null || true
done

args=()
args+=(--linux=linux)
for name in osrel cmdline initrd uname sbat; do
	if [ -f "$name" ]; then
		args+=("--${name}=${name}")
	fi
done
args+=(--phase=sysinit:ready)
args+=(--bank=sha256 --json=short)

systemd-measure calculate "${args[@]}" |
	jq -jr '.sha256[0].hash'
