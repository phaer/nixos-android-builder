"""Read firmware PCR values from the TPM and emit a keylime tpm_policy JSON.

These PCRs are populated by UEFI firmware and cannot be pre-calculated
at build time — they depend on the specific hardware, firmware version,
BIOS settings, and Secure Boot key enrollment.

When --verify-pcr11 is given, the script also reads PCR 11 from the
TPM and compares it against the expected value baked into the image
at build time (see the secure-boot NixOS module).  If they match,
PCR 11 is included in the output policy.  If not, the script exits
with an error.
"""

import argparse
import json
import sys
from pathlib import Path

FIRMWARE_PCRS = [0, 1, 2, 3, 7]
TPM_SYSFS = Path("/sys/class/tpm/tpm0/pcr-sha256")
EXPECTED_PCR11 = Path("/boot/expected-pcr11")


def read_pcr(pcr: int) -> str:
    """Read a single PCR value from sysfs.

    Returns the lowercase hex digest.
    """
    path = TPM_SYSFS / str(pcr)
    try:
        return path.read_text().strip().lower()
    except FileNotFoundError:
        print(
            f"Error: PCR {pcr} not found at {path}",
            file=sys.stderr,
        )
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Read firmware PCRs from the TPM"
            " and emit a keylime tpm_policy JSON."
        ),
    )
    parser.add_argument(
        "--verify-pcr11",
        action="store_true",
        help=(
            "Read PCR 11, verify it matches the expected"
            " value baked into the image, and include it"
            " in the output."
        ),
    )
    parser.add_argument(
        "--output",
        metavar="FILE",
        help="Write JSON to FILE instead of stdout.",
    )
    args = parser.parse_args()

    policy = {}
    for pcr in FIRMWARE_PCRS:
        digest = read_pcr(pcr)
        if len(digest) != 64:
            print(
                f"Error: PCR {pcr} returned unexpected"
                f" length ({len(digest)} chars,"
                " expected 64)",
                file=sys.stderr,
            )
            sys.exit(1)
        policy[str(pcr)] = [digest]

    if args.verify_pcr11:
        if not EXPECTED_PCR11.exists():
            print(
                "Error: --verify-pcr11 requires"
                f" {EXPECTED_PCR11} to exist."
                " Was the image built with PCR 11"
                " policy support?",
                file=sys.stderr,
            )
            sys.exit(1)

        expected = EXPECTED_PCR11.read_text().strip().lower()
        actual = read_pcr(11)

        if actual != expected:
            print(
                "Error: PCR 11 mismatch!\n"
                f"  expected: {expected}\n"
                f"  actual:   {actual}",
                file=sys.stderr,
            )
            sys.exit(1)

        policy["11"] = [actual]

    output = json.dumps(policy)
    if args.output:
        with open(args.output, "w") as f:
            f.write(output + "\n")
        print(
            f"Wrote PCR policy to {args.output}",
            file=sys.stderr,
        )
    else:
        print(output)


if __name__ == "__main__":
    main()
