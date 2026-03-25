"""Generate a measured boot reference state from an event log.

Thin CLI wrapper around the ``measured_boot_state`` library.

Usage::

    measure-boot-state \\
        -e /sys/kernel/security/tpm0/binary_bios_measurements \\
        -o refstate.json
"""

import argparse
import json
import sys
from typing import Any, Dict, Optional

from measured_boot_state import (
    UEFI_EVENTLOG,
    create_refstate,
    parse_eventlog,
)


def main() -> Optional[Dict[str, Any]]:
    parser = argparse.ArgumentParser(
        description=(
            "Create measured boot reference state"
        ),
    )
    parser.add_argument(
        "-e", "--eventlog",
        default=UEFI_EVENTLOG,
        help=(
            "Binary UEFI event log"
            f" (default: {UEFI_EVENTLOG})"
        ),
    )
    parser.add_argument(
        "-o", "--output", default="-",
        help="Output file (default: stdout)",
    )
    args = parser.parse_args()

    log_data = parse_eventlog(args.eventlog)
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
