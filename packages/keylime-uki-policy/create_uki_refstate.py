"""Generate a UKI measured boot reference state from an event log.

Parses the binary UEFI event log and extracts the reference state
for the UKI boot policy: SCRTM, firmware blobs, Secure Boot keys,
UKI application digest, and UKI PE section digests.

Usage::

    create-uki-refstate \\
        -e /sys/kernel/security/tpm0/binary_bios_measurements \\
        -o refstate.json
"""

import argparse
import json
import re
import subprocess
import sys
from typing import Any, Dict, List, Optional

import yaml


def parse_eventlog(path: str) -> Optional[Dict[str, Any]]:
    """Parse binary event log with tpm2_eventlog.

    Ignores stderr warnings (tpm2_eventlog warns about UKI's
    PCR 11 EV_IPL events which is expected for our boot chain).
    """
    result = subprocess.run(
        [
            "tpm2_eventlog", "--eventlog-version=2",
            path,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(
            f"tpm2_eventlog failed (rc={result.returncode}):"
            f" {result.stderr}",
            file=sys.stderr,
        )
        return None

    if result.stderr.strip():
        print(
            "tpm2_eventlog warnings:"
            f" {result.stderr.strip()}",
            file=sys.stderr,
        )

    try:
        return yaml.safe_load(result.stdout)
    except yaml.YAMLError as e:
        print(
            f"Failed to parse tpm2_eventlog YAML: {e}",
            file=sys.stderr,
        )
        return None


def event_to_sha256(
    event: Dict[str, Any],
) -> Dict[str, str]:
    """Extract sha256 digest from an event."""
    for digest in event.get("Digests", []):
        aid = digest.get("AlgorithmId", "")
        if aid == "sha256":
            return {"sha256": f"0x{digest['Digest']}"}
    return {}


def get_scrtm(
    events: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Find the EV_S_CRTM_VERSION event."""
    for event in events:
        et = event.get("EventType", "")
        if et == "EV_S_CRTM_VERSION":
            return {"scrtm": event_to_sha256(event)}
    return {}


def get_platform_firmware(
    events: List[Dict[str, Any]],
) -> Dict[str, List[Dict[str, str]]]:
    """Get firmware blob digests."""
    out = []
    for event in events:
        et = event.get("EventType", "")
        if et in (
            "EV_EFI_PLATFORM_FIRMWARE_BLOB",
            "EV_EFI_PLATFORM_FIRMWARE_BLOB2",
        ):
            out.append(event_to_sha256(event))
    return {"platform_firmware": out}


def get_keys(
    events: List[Dict[str, Any]],
) -> Dict[str, List[Dict[str, str]]]:
    """Get Secure Boot key signatures."""
    out: Dict[str, List[Dict[str, str]]] = {
        "pk": [], "kek": [], "db": [], "dbx": [],
    }
    for event in events:
        et = event.get("EventType", "")
        if et != "EV_EFI_VARIABLE_DRIVER_CONFIG":
            continue
        ev = event.get("Event", {})
        name = ev.get("UnicodeName", "").lower()
        if name not in out:
            continue
        data = ev.get("VariableData")
        if data is None:
            continue
        if isinstance(data, list):
            for entry in data:
                for key in entry.get("Keys", []):
                    so = key.get("SignatureOwner", "")
                    sd = key.get("SignatureData", "")
                    if so and sd:
                        out[name].append({
                            "SignatureOwner": so,
                            "SignatureData": f"0x{sd}",
                        })
    return out


def get_uki_digest(
    events: List[Dict[str, Any]],
) -> Dict[str, str]:
    """Get the UKI application digest from PCR 4.

    In a UKI boot there is exactly one non-firmware
    EV_EFI_BOOT_SERVICES_APPLICATION event.
    """
    fw_pat = re.compile(
        r"FvVol\(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\)"
        r"/FvFile\(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\)"
    )
    apps = []
    for event in events:
        et = event.get("EventType", "")
        if et != "EV_EFI_BOOT_SERVICES_APPLICATION":
            continue
        ev = event.get("Event", {})
        dp = ev.get("DevicePath", "")
        if fw_pat.match(str(dp)):
            continue
        apps.append(event_to_sha256(event))

    if len(apps) != 1:
        print(
            "Warning: expected 1 non-firmware"
            " EV_EFI_BOOT_SERVICES_APPLICATION,"
            f" got {len(apps)}",
            file=sys.stderr,
        )
    return apps[0] if apps else {}


def create_refstate(
    events: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Create a UKI measured boot reference state."""
    return {
        "scrtm_and_bios": [{
            **get_scrtm(events),
            **get_platform_firmware(events),
        }],
        **get_keys(events),
        "uki_digest": get_uki_digest(events),
    }


def main() -> Optional[Dict[str, Any]]:
    parser = argparse.ArgumentParser(
        description=(
            "Create UKI measured boot reference state"
        ),
    )
    parser.add_argument(
        "-e", "--eventlog-file", required=True,
        help="Binary UEFI event log",
    )
    parser.add_argument(
        "-o", "--output", default="-",
        help="Output file (default: stdout)",
    )
    args = parser.parse_args()

    log_data = parse_eventlog(args.eventlog_file)
    if not log_data:
        return None

    events = log_data.get("events", [])
    if not events:
        print("No events in event log", file=sys.stderr)
        return None

    refstate = create_refstate(events)

    if args.output == "-":
        json.dump(refstate, sys.stdout)
    else:
        with open(args.output, "w") as f:
            json.dump(refstate, f)

    return refstate


if __name__ == "__main__":
    result = main()
    sys.exit(0 if result else 1)
