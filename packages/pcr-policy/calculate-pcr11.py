"""Calculate the expected PCR 11 value for a UKI image.

systemd-stub measures each PE section of the UKI into PCR 11, then
systemd-pcrphase extends it with boot phase strings.  This script
reproduces that calculation offline using systemd-measure so that
the expected value can be fed into a keylime TPM policy.

Outputs the sha256 PCR 11 hash to stdout (64 hex characters, no newline).
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

UKI_SECTIONS = [".linux", ".osrel", ".cmdline", ".initrd", ".uname", ".sbat"]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Calculate the expected PCR 11 value for a UKI image.",
    )
    parser.add_argument("uki", type=Path, help="Path to the UKI (.efi) file.")
    args = parser.parse_args()

    if not args.uki.exists():
        print(f"Error: UKI file not found: {args.uki}", file=sys.stderr)
        sys.exit(1)

    with tempfile.TemporaryDirectory() as workdir:
        work = Path(workdir)

        local_uki = work / "uki.efi"
        shutil.copy2(args.uki, local_uki)
        local_uki.chmod(0o644)

        # Extract PE sections from the UKI
        extracted: dict[str, Path] = {}
        for section in UKI_SECTIONS:
            name = section.lstrip(".")
            out = work / name
            result = subprocess.run(
                [
                    "objcopy", "--dump-section",
                    f"{section}={out}", str(local_uki),
                ],
                capture_output=True,
            )
            if result.returncode == 0 and out.exists():
                extracted[name] = out

        # Build systemd-measure arguments
        linux = extracted["linux"]
        measure_args = [
            "systemd-measure", "calculate",
            f"--linux={linux}",
        ]
        for name in ["osrel", "cmdline", "initrd", "uname", "sbat"]:
            if name in extracted:
                measure_args.append(f"--{name}={extracted[name]}")
        measure_args += [
            "--phase=sysinit:ready",
            "--bank=sha256",
            "--json=short",
        ]

        result = subprocess.run(
            measure_args,
            capture_output=True, text=True, check=True,
        )
        data = json.loads(result.stdout)
        print(data["sha256"][0]["hash"], end="")


if __name__ == "__main__":
    main()
