"""Report TPM PCR values to the auto-enrollment server.

Reads firmware PCRs (0-3, 7) and PCR 11 from the TPM, verifies
PCR 11 against the expected value on the ESP, then POSTs the full
policy to the auto-enrollment HTTPS endpoint on the attestation
server.

The agent UUID is read from the keylime agent's ``agent_data.json``
file, which stores the EK hash (== the UUID in ``hash_ek`` mode)
as a byte array of the hex-encoded SHA-256 digest.

Environment variables:
    KEYLIME_ENROLL_PORT     Port for enrollment endpoint (default: 8893)
    KEYLIME_AGENT_UUID      Override UUID (skips agent_data.json)
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
import ssl
from pathlib import Path

FIRMWARE_PCRS = [0, 1, 2, 3, 7]
TPM_SYSFS = Path("/sys/class/tpm/tpm0/pcr-sha256")
EXPECTED_PCR11 = Path("/boot/expected-pcr11")
ATTESTATION_SERVER = Path("/boot/attestation-server.json")
AGENT_DATA = Path("/var/lib/keylime/agent_data.json")


def read_pcr(pcr: int) -> str:
    """Read a single PCR value from sysfs."""
    path = TPM_SYSFS / str(pcr)
    try:
        return path.read_text().strip().lower()
    except FileNotFoundError:
        print(f"Error: PCR {pcr} not found at {path}", file=sys.stderr)
        sys.exit(1)


def read_policy() -> dict:
    """Read firmware PCRs and verified PCR 11."""
    policy: dict = {}

    for pcr in FIRMWARE_PCRS:
        digest = read_pcr(pcr)
        if len(digest) != 64:
            print(
                f"Error: PCR {pcr} returned unexpected length"
                f" ({len(digest)} chars, expected 64)",
                file=sys.stderr,
            )
            sys.exit(1)
        policy[str(pcr)] = [digest]

    if not EXPECTED_PCR11.exists():
        print(
            f"Error: {EXPECTED_PCR11} not found.\n"
            "Run: configure-disk-image set-pcr11 --device <image>",
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


def get_agent_uuid(timeout: int = 60) -> str:
    """Read the agent UUID from agent_data.json.

    The keylime agent stores the EK hash as a byte array in
    ``ek_hash`` — the UTF-8 bytes of the hex-encoded SHA-256
    digest of the EK public key.  This is the same value used
    as the agent UUID in ``hash_ek`` mode.

    Waits up to *timeout* seconds for the field to appear.
    If ``KEYLIME_AGENT_UUID`` is set, uses that directly.
    """
    env_uuid = os.environ.get("KEYLIME_AGENT_UUID")
    if env_uuid:
        return env_uuid

    deadline = time.monotonic() + timeout
    while True:
        if AGENT_DATA.exists():
            try:
                with open(AGENT_DATA) as f:
                    data = json.load(f)
                ek_hash_bytes = data.get("ek_hash")
                if ek_hash_bytes and isinstance(ek_hash_bytes, list):
                    return bytes(ek_hash_bytes).decode("ascii")
            except (json.JSONDecodeError, ValueError, KeyError):
                pass

        if time.monotonic() >= deadline:
            print(
                "Error: timed out waiting for ek_hash"
                f" in {AGENT_DATA}",
                file=sys.stderr,
            )
            sys.exit(1)

        time.sleep(2)


def get_enroll_config() -> tuple[str, str]:
    """Determine the enrollment server URL and CA cert path."""
    port = os.environ.get("KEYLIME_ENROLL_PORT", "8893")

    if not ATTESTATION_SERVER.exists():
        print(
            f"Error: {ATTESTATION_SERVER} not found.",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(ATTESTATION_SERVER) as f:
        data = json.load(f)

    ip = data.get("ip")
    if not ip:
        print(
            "Error: attestation-server.json missing 'ip'",
            file=sys.stderr,
        )
        sys.exit(1)

    ca_cert = data.get("ca_cert")
    if not ca_cert:
        print(
            "Error: attestation-server.json missing 'ca_cert'",
            file=sys.stderr,
        )
        sys.exit(1)

    url = f"https://{ip}:{port}"
    return url.rstrip("/"), ca_cert


def main() -> None:
    policy = read_policy()
    uuid = get_agent_uuid()
    url, ca_cert = get_enroll_config()

    print(f"Agent UUID: {uuid}", file=sys.stderr)
    print(
        f"PCRs: {', '.join(sorted(policy.keys(), key=int))}",
        file=sys.stderr,
    )
    print(f"Enrollment server: {url}", file=sys.stderr)

    endpoint = f"{url}/v1/report_pcrs"
    payload = json.dumps({"uuid": uuid, "policy": policy}).encode()

    ctx = ssl.create_default_context(cadata=ca_cert)

    req = urllib.request.Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, context=ctx) as resp:
            body = json.loads(resp.read())
    except urllib.error.URLError as e:
        print(
            f"Error: POST to {endpoint} failed: {e}",
            file=sys.stderr,
        )
        sys.exit(1)
    except json.JSONDecodeError:
        print(
            f"Error: unexpected response from {endpoint}",
            file=sys.stderr,
        )
        sys.exit(1)

    if body.get("status") == "accepted":
        print("PCR report accepted by enrollment server.", file=sys.stderr)
    else:
        print(
            f"Error: server response: {json.dumps(body)}",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
