#!/usr/bin/env bash
#
# Read firmware PCR values (0-3, 7) from the TPM and emit them as JSON.
#
# These PCRs are populated by UEFI firmware and cannot be pre-calculated
# at build time — they depend on the specific hardware, firmware version,
# BIOS settings, and Secure Boot key enrollment.
#
# Usage: read-firmware-pcrs [--pcr11] [--output FILE]
#
#   --pcr11       Also include PCR 11 (UKI + pcrphase measurement).
#                 Useful to capture a complete baseline from a running
#                 machine instead of pre-calculating PCR 11 from the UKI.
#
#   --output FILE Write JSON to FILE instead of stdout.
#
# Output format (suitable as keylime --tpm_policy):
#   {"0": ["<hex>"], "1": ["<hex>"], "2": ["<hex>"], "3": ["<hex>"], "7": ["<hex>"]}

set -euo pipefail

PCRS="0,1,2,3,7"
OUTPUT=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--pcr11)
		PCRS="0,1,2,3,7,11"
		shift
		;;
	--output)
		OUTPUT="${2:?--output requires a filename}"
		shift 2
		;;
	--output=*)
		OUTPUT="${1#*=}"
		shift
		;;
	-h | --help)
		echo "Usage: read-firmware-pcrs [--pcr11] [--output FILE]"
		echo ""
		echo "Read firmware PCR values from the TPM and emit a keylime tpm_policy JSON."
		echo ""
		echo "Options:"
		echo "  --pcr11       Also include PCR 11 in the output"
		echo "  --output FILE Write JSON to FILE instead of stdout"
		echo "  -h, --help    Show this help message"
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	esac
done

# Build a JSON object by reading each PCR individually
policy="{"
first=true
for pcr in ${PCRS//,/ }; do
	hex=$(tpm2_pcrread "sha256:${pcr}" -Q -o /dev/stdout | od -An -tx1 | tr -d ' \n')

	if [ ${#hex} -ne 64 ]; then
		echo "ERROR: PCR ${pcr} returned unexpected length (${#hex} chars, expected 64)" >&2
		exit 1
	fi

	if [ "$first" = true ]; then
		first=false
	else
		policy+=", "
	fi
	policy+="\"${pcr}\": [\"${hex}\"]"
done
policy+="}"

if [ -n "$OUTPUT" ]; then
	echo "$policy" >"$OUTPUT"
	echo "Wrote PCR policy to $OUTPUT" >&2
else
	echo "$policy"
fi
