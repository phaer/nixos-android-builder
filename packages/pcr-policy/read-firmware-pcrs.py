"""Read firmware PCR values from the TPM and emit a keylime tpm_policy JSON.

Reads firmware PCRs (0–3, 7) and PCR 11 from the TPM and outputs
them as a keylime-compatible tpm_policy JSON object.

These PCRs are populated by UEFI firmware and cannot be pre-calculated
at build time — they depend on the specific hardware, firmware version,
BIOS settings, and Secure Boot key enrollment.

The --save flag writes the current PCR baseline to a JSON file for
later comparison.  The --diff flag compares the current PCR values
against a previously saved baseline and reports any changes.
"""

import argparse
import json
import sys
from pathlib import Path

FIRMWARE_PCRS = [0, 1, 2, 3, 7]
TPM_SYSFS = Path("/sys/class/tpm/tpm0/pcr-sha256")
DEFAULT_BASELINE = Path("/var/lib/keylime/pcr-baseline.json")


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
    """Read all firmware PCRs and PCR 11."""
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

    policy["11"] = [read_pcr(11)]
    return policy


def save_baseline(policy: dict, path: Path) -> None:
    """Save PCR policy as a baseline file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(policy, f, indent=2)
        f.write("\n")
    print(f"✓ PCR baseline saved to {path}", file=sys.stderr)


def diff_baseline(policy: dict, path: Path) -> bool:
    """Compare current PCR values against a saved baseline.

    Returns True if they match, False if there are differences.
    """
    if not path.exists():
        print(
            f"Error: baseline file {path} not found.\n"
            "Run: read-firmware-pcrs --save first.",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(path) as f:
        baseline = json.load(f)

    changed = False
    for pcr in sorted(policy.keys(), key=int):
        current = policy[pcr][0]
        if pcr not in baseline:
            print(f"  PCR {pcr}: NEW {current}", file=sys.stderr)
            changed = True
        elif baseline[pcr][0] != current:
            print(
                f"  PCR {pcr}: CHANGED\n"
                f"    was: {baseline[pcr][0]}\n"
                f"    now: {current}",
                file=sys.stderr,
            )
            changed = True
        else:
            print(f"  PCR {pcr}: unchanged", file=sys.stderr)

    # Check for PCRs in baseline but not in current
    for pcr in sorted(baseline.keys(), key=int):
        if pcr not in policy:
            print(
                f"  PCR {pcr}: REMOVED (was {baseline[pcr][0]})",
                file=sys.stderr,
            )
            changed = True

    return not changed


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Read firmware PCRs from the TPM"
            " and emit a keylime tpm_policy JSON."
        ),
    )
    parser.add_argument(
        "--output",
        metavar="FILE",
        help="Write JSON to FILE instead of stdout.",
    )
    parser.add_argument(
        "--save",
        nargs="?",
        const=str(DEFAULT_BASELINE),
        metavar="FILE",
        help=(
            "Save the current PCR values as a baseline."
            f" Default: {DEFAULT_BASELINE}"
        ),
    )
    parser.add_argument(
        "--diff",
        nargs="?",
        const=str(DEFAULT_BASELINE),
        metavar="FILE",
        help=(
            "Compare current PCRs against a saved baseline"
            " and report changes."
            f" Default: {DEFAULT_BASELINE}"
        ),
    )
    args = parser.parse_args()

    policy = read_policy()

    if args.save:
        save_baseline(policy, Path(args.save))

    if args.diff:
        match = diff_baseline(policy, Path(args.diff))
        if not match:
            print(
                "\n⚠ PCR values differ from baseline."
                " Re-enrollment may be needed.",
                file=sys.stderr,
            )
            sys.exit(2)
        else:
            print(
                "\n✓ All PCRs match baseline.",
                file=sys.stderr,
            )

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
