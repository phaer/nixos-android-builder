"""Report measured boot state to the auto-enrollment server.

Generates a measured boot reference state from the UEFI
event log using ``create-uki-refstate`` and POSTs it to the
auto-enrollment HTTPS endpoint on the attestation server.

The agent UUID is read from the keylime agent's
``agent_data.json`` file, which stores the EK hash (== the
UUID in ``hash_ek`` mode) as a byte array of the hex-encoded
SHA-256 digest.

Environment variables:
    KEYLIME_ENROLL_PORT     Port for enrollment endpoint
    KEYLIME_AGENT_UUID      Override UUID
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
import ssl
from pathlib import Path

TPM_SYSFS = Path("/sys/class/tpm/tpm0/pcr-sha256")
UEFI_EVENTLOG = Path(
    "/sys/kernel/security/tpm0/binary_bios_measurements",
)
ATTESTATION_SERVER = Path("/boot/attestation-server.json")
AGENT_DATA = Path("/var/lib/keylime/agent_data.json")


def generate_mb_refstate() -> dict:
    """Generate measured boot reference state."""
    if not UEFI_EVENTLOG.exists():
        print(
            "Error: UEFI event log not found at"
            f" {UEFI_EVENTLOG}",
            file=sys.stderr,
        )
        sys.exit(1)

    with tempfile.NamedTemporaryFile(
        mode="r", suffix=".json", delete=False,
    ) as tmp:
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            [
                "create-uki-refstate",
                "-e", str(UEFI_EVENTLOG),
                "-o", tmp_path,
            ],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            output = f"{result.stdout} {result.stderr}"
            print(
                "Error: create-uki-refstate"
                f" failed: {output.strip()}",
                file=sys.stderr,
            )
            sys.exit(1)

        with open(tmp_path) as f:
            return json.load(f)
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def get_agent_uuid(timeout: int = 60) -> str:
    """Read the agent UUID from agent_data.json."""
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
                if ek_hash_bytes and isinstance(
                    ek_hash_bytes, list,
                ):
                    return bytes(
                        ek_hash_bytes,
                    ).decode("ascii")
            except (
                json.JSONDecodeError, ValueError, KeyError,
            ):
                pass

        if time.monotonic() >= deadline:
            print(
                "Error: timed out waiting for"
                f" ek_hash in {AGENT_DATA}",
                file=sys.stderr,
            )
            sys.exit(1)

        time.sleep(2)


def get_enroll_config() -> tuple[str, str]:
    """Determine enrollment server URL and CA cert."""
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
            "Error: attestation-server.json"
            " missing 'ip'",
            file=sys.stderr,
        )
        sys.exit(1)

    ca_cert = data.get("ca_cert")
    if not ca_cert:
        print(
            "Error: attestation-server.json"
            " missing 'ca_cert'",
            file=sys.stderr,
        )
        sys.exit(1)

    url = f"https://{ip}:{port}"
    return url.rstrip("/"), ca_cert


def main() -> None:
    mb_refstate = generate_mb_refstate()
    uuid = get_agent_uuid()
    url, ca_cert = get_enroll_config()

    print(f"Agent UUID: {uuid}", file=sys.stderr)
    print(
        "MB refstate keys:"
        f" {', '.join(sorted(mb_refstate.keys()))}",
        file=sys.stderr,
    )
    print(f"Enrollment server: {url}", file=sys.stderr)

    endpoint = f"{url}/v1/report_pcrs"
    payload = json.dumps({
        "uuid": uuid,
        "mb_refstate": mb_refstate,
    }).encode()

    ctx = ssl.create_default_context(cadata=ca_cert)

    req = urllib.request.Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(
            req, context=ctx,
        ) as resp:
            body = json.loads(resp.read())
    except urllib.error.URLError as e:
        print(
            f"Error: POST to {endpoint} failed: {e}",
            file=sys.stderr,
        )
        sys.exit(1)
    except json.JSONDecodeError:
        print(
            "Error: unexpected response from"
            f" {endpoint}",
            file=sys.stderr,
        )
        sys.exit(1)

    if body.get("status") == "accepted":
        print(
            "Measured boot report accepted.",
            file=sys.stderr,
        )
    else:
        print(
            "Error: server response:"
            f" {json.dumps(body)}",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
