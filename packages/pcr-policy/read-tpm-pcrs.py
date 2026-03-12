"""Read PCR values from the TPM and emit a keylime tpm_policy JSON.

Reads firmware PCRs (0–3, 7) and PCR 11 (UKI + boot phases) from the
TPM sysfs.  Firmware PCRs depend on the specific hardware, firmware
version, BIOS settings, and Secure Boot key enrollment.  PCR 11 is
verified against the expected value baked into the image at build
time (see the secure-boot NixOS module); a mismatch causes the
script to exit with an error.

When run on a terminal, a QR code of the policy is displayed on
stderr for easy transfer from machines with limited connectivity.
"""

import json
import sys
from pathlib import Path

import qrcode  # type: ignore[import-untyped]

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


def read_policy() -> dict:
    """Read all firmware PCRs and PCR 11 (verified)."""
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

    if not EXPECTED_PCR11.exists():
        print(
            f"Error: {EXPECTED_PCR11} not found.\n"
            "Run: configure-disk-image set-pcr11"
            " --device <image>",
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

    return policy


def main() -> None:
    policy = read_policy()
    output = json.dumps(policy)
    print(output)

    if sys.stderr.isatty():
        qr = qrcode.QRCode(
            error_correction=qrcode.constants.ERROR_CORRECT_L,
        )
        qr.add_data(output)
        qr.make(fit=True)
        print(file=sys.stderr)
        qr.print_tty(out=sys.stderr)


if __name__ == "__main__":
    main()
