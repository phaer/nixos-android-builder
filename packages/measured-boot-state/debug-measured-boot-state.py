"""Debug measured boot state mismatches.

Diagnoses why attestation fails by replaying the UEFI event log,
comparing PCR values against the TPM, and diffing the current
reference state against an enrolled one.

Modes:

    # Diagnose live system against enrolled refstate
    debug-measured-boot-state --refstate enrolled.json

    # Diagnose with explicit event log (offline)
    debug-measured-boot-state --eventlog log.bin --refstate enrolled.json

    # Diff two refstate files
    debug-measured-boot-state --diff old.json new.json

    # Just show PCR replay vs TPM (no refstate needed)
    debug-measured-boot-state
"""

import argparse
import json
import sys
from pathlib import Path

from measured_boot_state import (
    UEFI_EVENTLOG,
    TPM_SYSFS,
    create_refstate,
    diff_refstates,
    parse_eventlog,
    read_tpm_pcrs,
    replay_pcrs,
)

# PCRs relevant to the UKI measured boot policy.
POLICY_PCRS = [0, 1, 2, 3, 4, 5, 7, 9, 11]


def print_pcr_comparison(
    replayed: dict, tpm: dict,
) -> bool:
    """Print PCR replay vs TPM comparison.

    Returns True if all relevant PCRs match.
    """
    print("PCR replay vs TPM:")
    all_match = True
    for pcr in POLICY_PCRS:
        r = replayed.get(pcr)
        t = tpm.get(pcr)
        if r is None:
            print(f"  PCR {pcr:>2}: - (not in event log)")
            continue
        if t is None:
            print(f"  PCR {pcr:>2}: - (not in TPM sysfs)")
            continue
        if r == t:
            print(f"  PCR {pcr:>2}: \u2713 match")
        else:
            print(f"  PCR {pcr:>2}: \u2717 MISMATCH")
            print(f"    replayed: {r}")
            print(f"    tpm:      {t}")
            all_match = False
    return all_match


def _trunc(s: str, n: int = 24) -> str:
    """Truncate a hex string for display."""
    if len(s) > n:
        return s[:n] + "..."
    return s


def print_refstate_diff(diff: dict) -> bool:
    """Print a structured refstate diff.

    Returns True if refstates are identical.
    """
    print("Refstate diff:")
    all_same = True
    for field, change in diff.items():
        if change is None:
            print(f"  {field}: unchanged")
            continue
        all_same = False
        if "old" in change and "new" in change:
            # Digest change
            old_v = change["old"].get("sha256", str(change["old"]))
            new_v = change["new"].get("sha256", str(change["new"]))
            print(f"  {field}: CHANGED")
            print(f"    old: {old_v}")
            print(f"    new: {new_v}")
        elif "added" in change and "removed" in change:
            if "old_count" in change:
                # Firmware blobs
                print(
                    f"  {field}: CHANGED"
                    f" ({change['old_count']}"
                    f" -> {change['new_count']})"
                )
                for d in change["removed"]:
                    print(f"    - {_trunc(d)}")
                for d in change["added"]:
                    print(f"    + {_trunc(d)}")
            else:
                # Signature list
                added = change["added"]
                removed = change["removed"]
                parts = []
                if added:
                    parts.append(
                        f"+{len(added)} added"
                    )
                if removed:
                    parts.append(
                        f"-{len(removed)} removed"
                    )
                print(
                    f"  {field}: CHANGED"
                    f" ({', '.join(parts)})"
                )
                for s in removed:
                    owner = s["SignatureOwner"]
                    data = _trunc(
                        s["SignatureData"], 20,
                    )
                    print(
                        f"    - Owner={owner}"
                        f" Data={data}"
                    )
                for s in added:
                    owner = s["SignatureOwner"]
                    data = _trunc(
                        s["SignatureData"], 20,
                    )
                    print(
                        f"    + Owner={owner}"
                        f" Data={data}"
                    )
    return all_same


def print_event_summary(
    events: list, refstate: dict,
) -> None:
    """Print per-event check against refstate.

    Checks pinned fields (SCRTM, firmware, UKI, Secure Boot
    keys) against the refstate and reports pass/fail.
    """
    print("\nPolicy evaluation (pinned fields):")

    bios = refstate.get("scrtm_and_bios", [{}])
    ref_scrtm = (
        bios[0].get("scrtm", {}) if bios else {}
    )
    ref_fw = (
        bios[0].get("platform_firmware", [])
        if bios else []
    )
    ref_uki = refstate.get("uki_digest", {})
    ref_keys = {
        k: refstate.get(k, [])
        for k in ("pk", "kek", "db", "dbx")
    }

    import re
    fw_pat = re.compile(
        r"FvVol\(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\)"
        r"/FvFile\(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\)"
    )
    fw_idx = 0

    for event in events:
        et = event.get("EventType", "")
        pcr = event.get("PCRIndex", "?")
        digests = event.get("Digests", [])
        sha = ""
        for d in digests:
            if d.get("AlgorithmId") == "sha256":
                sha = f"0x{d['Digest']}"
                break

        if et == "EV_S_CRTM_VERSION":
            expected = ref_scrtm.get("sha256", "")
            ok = sha == expected
            mark = "\u2713" if ok else "\u2717 FAILED"
            print(
                f"  PCR {pcr:>2}"
                f" {et}: {mark}"
            )
            if not ok:
                print(f"    expected: {expected}")
                print(f"    got:      {sha}")

        elif et in (
            "EV_EFI_PLATFORM_FIRMWARE_BLOB",
            "EV_EFI_PLATFORM_FIRMWARE_BLOB2",
        ):
            expected = ""
            if fw_idx < len(ref_fw):
                expected = ref_fw[fw_idx].get(
                    "sha256", ""
                )
            ok = sha == expected
            mark = "\u2713" if ok else "\u2717 FAILED"
            print(
                f"  PCR {pcr:>2}"
                f" {et}"
                f" #{fw_idx}: {mark}"
            )
            if not ok:
                print(f"    expected: {expected}")
                print(f"    got:      {sha}")
            fw_idx += 1

        elif et == "EV_EFI_BOOT_SERVICES_APPLICATION":
            ev = event.get("Event", {})
            dp = ev.get("DevicePath", "")
            if fw_pat.match(str(dp)):
                continue
            expected = ref_uki.get("sha256", "")
            ok = sha == expected
            mark = "\u2713" if ok else "\u2717 FAILED"
            print(
                f"  PCR {pcr:>2}"
                f" {et}: {mark}"
            )
            if not ok:
                print(f"    expected: {expected}")
                print(f"    got:      {sha}")
                print(
                    "    \u2192 UKI image changed;"
                    " re-enroll with new refstate"
                )

        elif et == "EV_EFI_VARIABLE_DRIVER_CONFIG":
            ev = event.get("Event", {})
            name = ev.get("UnicodeName", "")
            name_lower = name.lower()
            if name_lower in ref_keys:
                # Just report presence — deep key
                # comparison is done in refstate diff
                print(
                    f"  PCR {pcr:>2}"
                    f" {et}"
                    f" {name}: \u2713 (see refstate diff"
                    f" for key details)"
                )


def cmd_diagnose(args: argparse.Namespace) -> int:
    """Diagnose event log against TPM and refstate."""
    eventlog_path = args.eventlog
    if not Path(eventlog_path).exists():
        print(
            f"Error: event log not found: {eventlog_path}",
            file=sys.stderr,
        )
        return 1

    log_data = parse_eventlog(eventlog_path)
    if not log_data:
        return 1
    events = log_data.get("events", [])
    if not events:
        print("No events in event log", file=sys.stderr)
        return 1

    exit_code = 0

    # PCR replay vs TPM
    replayed = replay_pcrs(events)
    tpm = read_tpm_pcrs(args.tpm_sysfs)
    if tpm:
        pcr_ok = print_pcr_comparison(replayed, tpm)
        if not pcr_ok:
            exit_code = 2
    else:
        print(
            f"TPM sysfs not available at {args.tpm_sysfs};"
            " showing replayed PCRs only:"
        )
        for pcr in POLICY_PCRS:
            val = replayed.get(pcr, "(none)")
            print(f"  PCR {pcr:>2}: {val}")
    print()

    # Refstate diff
    if args.refstate:
        if not Path(args.refstate).exists():
            print(
                f"Error: refstate not found:"
                f" {args.refstate}",
                file=sys.stderr,
            )
            return 1
        with open(args.refstate) as f:
            enrolled = json.load(f)
        current = create_refstate(events)
        diff = diff_refstates(enrolled, current)
        ref_ok = print_refstate_diff(diff)
        if not ref_ok:
            exit_code = max(exit_code, 2)

        print_event_summary(events, enrolled)
    else:
        print(
            "No --refstate given; skipping"
            " refstate comparison."
        )
        print(
            "Tip: pass --refstate to compare"
            " against an enrolled refstate."
        )

    return exit_code


def cmd_diff(args: argparse.Namespace) -> int:
    """Diff two refstate JSON files."""
    for path in (args.old, args.new):
        if not Path(path).exists():
            print(
                f"Error: file not found: {path}",
                file=sys.stderr,
            )
            return 1

    with open(args.old) as f:
        old = json.load(f)
    with open(args.new) as f:
        new = json.load(f)

    diff = diff_refstates(old, new)
    same = print_refstate_diff(diff)
    return 0 if same else 2


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Debug measured boot policy mismatches"
        ),
    )
    sub = parser.add_subparsers(dest="command")

    # Default: diagnose mode
    diag = sub.add_parser(
        "diagnose",
        help="Diagnose event log against TPM and refstate",
    )
    diag.add_argument(
        "--eventlog", "-e",
        default=UEFI_EVENTLOG,
        help=(
            "Binary UEFI event log"
            f" (default: {UEFI_EVENTLOG})"
        ),
    )
    diag.add_argument(
        "--refstate", "-r",
        help="Enrolled refstate JSON to compare against",
    )
    diag.add_argument(
        "--tpm-sysfs",
        default=TPM_SYSFS,
        help=f"TPM PCR sysfs path (default: {TPM_SYSFS})",
    )

    # Diff mode
    df = sub.add_parser(
        "diff",
        help="Diff two refstate JSON files",
    )
    df.add_argument("old", help="Old refstate JSON")
    df.add_argument("new", help="New refstate JSON")

    args = parser.parse_args()

    if args.command == "diff":
        sys.exit(cmd_diff(args))
    elif args.command == "diagnose":
        sys.exit(cmd_diagnose(args))
    else:
        # Default to diagnose if no subcommand
        args.eventlog = UEFI_EVENTLOG
        args.refstate = None
        args.tpm_sysfs = TPM_SYSFS
        sys.exit(cmd_diagnose(args))


if __name__ == "__main__":
    main()
