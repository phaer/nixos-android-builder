"""Auto-enrollment daemon for Keylime agents.

Runs an HTTPS server that accepts measured boot reports from agents and
polls the registrar for newly registered agents.  When an agent is
both registered in the registrar *and* has submitted its report,
it is automatically enrolled with the verifier using:

- A measured boot reference state (``--mb_refstate``) derived from the
  agent's UEFI event log, validated by the ``uki`` policy (covering
  SCRTM, firmware blobs, Secure Boot keys, and the UKI digest).

Environment variables:
    KEYLIME_REGISTRAR_IP    Registrar address (default: 127.0.0.1)
    KEYLIME_REGISTRAR_PORT  Registrar TLS port (default: 8891)
    KEYLIME_VERIFIER_IP     Verifier address (default: 127.0.0.1)
    KEYLIME_VERIFIER_PORT   Verifier port (default: 8881)
    KEYLIME_TLS_DIR         Directory containing mTLS certs
    KEYLIME_POLL_INTERVAL   Seconds between polls (default: 10)
    KEYLIME_ENROLL_PORT     HTTPS port for report endpoint (default: 8893)
    KEYLIME_LOG_LEVEL       DEBUG, INFO, WARNING, ERROR (default: INFO)
"""

import json
import logging
import os
import signal
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

LOG_LEVEL = os.environ.get("KEYLIME_LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("auto-enroll")

REGISTRAR_IP = os.environ.get("KEYLIME_REGISTRAR_IP", "127.0.0.1")
REGISTRAR_PORT = os.environ.get("KEYLIME_REGISTRAR_PORT", "8891")
VERIFIER_IP = os.environ.get("KEYLIME_VERIFIER_IP", "127.0.0.1")
VERIFIER_PORT = os.environ.get("KEYLIME_VERIFIER_PORT", "8881")
TLS_DIR = os.environ.get("KEYLIME_TLS_DIR", "/var/lib/keylime/tls")
POLL_INTERVAL = int(os.environ.get("KEYLIME_POLL_INTERVAL", "10"))
ENROLL_PORT = int(os.environ.get("KEYLIME_ENROLL_PORT", "8893"))

CA_CERT = os.path.join(TLS_DIR, "ca-cert.pem")
SERVER_CERT = os.path.join(TLS_DIR, "server-cert.pem")
SERVER_KEY = os.path.join(TLS_DIR, "server-key.pem")
CLIENT_CERT = os.path.join(TLS_DIR, "client-cert.pem")
CLIENT_KEY = os.path.join(TLS_DIR, "client-key.pem")


def make_mtls_context() -> ssl.SSLContext:
    """Create an SSL context with client certificate for mTLS."""
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.load_cert_chain(CLIENT_CERT, CLIENT_KEY)
    ctx.load_verify_locations(CA_CERT)
    # Accessed via IP which may not match the cert's CN.
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_REQUIRED
    return ctx


mtls_ctx = None


def get_mtls_ctx() -> ssl.SSLContext:
    """Lazily initialise the mTLS context."""
    global mtls_ctx
    if mtls_ctx is None:
        mtls_ctx = make_mtls_context()
    return mtls_ctx


def api_get(url: str) -> dict:
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=get_mtls_ctx()) as resp:
        return json.loads(resp.read())


def api_post(url: str, body: dict) -> dict:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, context=get_mtls_ctx()) as resp:
        return json.loads(resp.read())


# Stores {uuid: {"mb_refstate": dict}}
agent_reports: dict[str, dict] = {}
agent_reports_lock = threading.Lock()


def validate_report(report: dict) -> str | None:
    """Validate format of a measured boot report from an agent.

    Expected format::

        {
            "uuid": "<agent-uuid>",
            "mb_refstate": { ... }
        }

    Returns an error message string, or None if valid.
    """
    if not isinstance(report, dict):
        return "report must be a JSON object"

    uuid = report.get("uuid")
    if not uuid or not isinstance(uuid, str):
        return "missing or invalid 'uuid'"

    mb_refstate = report.get("mb_refstate")
    if not isinstance(mb_refstate, dict) or not mb_refstate:
        return "missing or invalid 'mb_refstate'"

    return None


class EnrollHandler(BaseHTTPRequestHandler):
    """Handle POST /v1/report_pcrs from agents."""

    def log_message(self, fmt, *args):
        log.info("HTTP %s", fmt % args)

    def do_POST(self):  # noqa: N802
        if self.path != "/v1/report_pcrs":
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(content_length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_error(400, "Invalid JSON")
            return

        error = validate_report(body)
        if error:
            log.warning("Rejected report: %s", error)
            self.send_error(400, error)
            return

        uuid = body["uuid"]
        with agent_reports_lock:
            agent_reports[uuid] = {
                "mb_refstate": body["mb_refstate"],
            }

        log.info(
            "Accepted measured boot report from %s"
            " (refstate keys: %s)",
            uuid,
            ", ".join(sorted(body["mb_refstate"].keys())),
        )

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "accepted"}).encode())


def start_https_server() -> HTTPServer:
    """Start the HTTPS server for receiving reports."""
    server = HTTPServer(("0.0.0.0", ENROLL_PORT), EnrollHandler)

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(SERVER_CERT, SERVER_KEY)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    log.info("HTTPS server listening on port %d", ENROLL_PORT)

    return server


def get_registered_uuids() -> set[str]:
    """Fetch all agent UUIDs from the registrar."""
    url = f"https://{REGISTRAR_IP}:{REGISTRAR_PORT}/v2.5/agents/"
    try:
        data = api_get(url)
        return set(data.get("results", {}).get("uuids", []))
    except Exception as e:
        log.warning("Failed to query registrar: %s", e)
        return set()


def get_enrolled_uuids() -> set[str]:
    """Fetch all agent UUIDs from the verifier."""
    url = f"https://{VERIFIER_IP}:{VERIFIER_PORT}/v2.5/agents/"
    try:
        data = api_get(url)
        # Verifier wraps each UUID in a single-element list:
        # {"uuids": [["uuid1"], ["uuid2"], ...]}
        return {
            entry[0]
            for entry in data.get("results", {}).get("uuids", [])
            if entry
        }
    except Exception as e:
        log.warning("Failed to query verifier: %s", e)
        return set()


def enroll_agent(uuid: str, report: dict) -> bool:
    """Enroll an agent with the verifier.

    Uses ``--mb_refstate`` for the measured boot event log policy.
    PCR 11 is covered by the measured boot quote (keylime includes
    it in MEASUREDBOOT_PCRS automatically).
    """
    mb_refstate = report["mb_refstate"]

    log.info(
        "Enrolling agent %s (mb_refstate keys: %s)",
        uuid,
        ", ".join(sorted(mb_refstate.keys())),
    )

    # Write refstate to a temp file — keylime_tenant reads from a path.
    refstate_file = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False,
        ) as f:
            json.dump(mb_refstate, f)
            refstate_file = f.name

        cmd = [
            "keylime_tenant",
            "--push-model",
            "-c", "add",
            "-t", "0.0.0.0",
            "-u", uuid,
            "-r", REGISTRAR_IP,
            "-rp", REGISTRAR_PORT,
            "-v", VERIFIER_IP,
            "-vp", VERIFIER_PORT,
            "--mb_refstate", refstate_file,
        ]

        log.debug("Running: %s", " ".join(cmd))
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
        )
    finally:
        if refstate_file:
            try:
                os.unlink(refstate_file)
            except OSError:
                pass

    if result.returncode == 0:
        log.info("Successfully enrolled agent %s", uuid)
        return True

    output = f"{result.stdout.strip()} {result.stderr.strip()}"

    if "conflict" in output.lower():
        log.info("Agent %s already enrolled, skipping", uuid)
        return True

    log.error("Failed to enroll agent %s: %s", uuid, output)
    return False


def main() -> None:
    running = True

    def handle_signal(signum, frame):
        nonlocal running
        log.info("Received signal %d, shutting down", signum)
        running = False

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    log.info("Starting auto-enrollment daemon")
    log.info(
        "Registrar: %s:%s  Verifier: %s:%s",
        REGISTRAR_IP, REGISTRAR_PORT, VERIFIER_IP, VERIFIER_PORT,
    )
    log.info("Poll interval: %ds", POLL_INTERVAL)

    for cert_path in [CA_CERT, SERVER_CERT, SERVER_KEY,
                      CLIENT_CERT, CLIENT_KEY]:
        if not os.path.isfile(cert_path):
            log.error("Required cert/key file missing: %s", cert_path)
            sys.exit(1)

    url = f"https://{REGISTRAR_IP}:{REGISTRAR_PORT}/v2.5/agents/"
    try:
        api_get(url)
        log.info("Registrar reachable")
    except Exception as e:
        log.warning(
            "Registrar not reachable at startup (will retry): %s", e,
        )

    https_server = start_https_server()

    while running:
        try:
            registered = get_registered_uuids()
            enrolled = get_enrolled_uuids()
            new_agents = registered - enrolled

            with agent_reports_lock:
                reported = set(agent_reports.keys())

            # Only enroll agents that have both registered AND
            # submitted their measured boot report.
            ready = new_agents & reported

            if new_agents - reported:
                waiting = new_agents - reported
                log.debug(
                    "Waiting for reports from: %s",
                    ", ".join(sorted(waiting)),
                )

            for uuid in sorted(ready):
                with agent_reports_lock:
                    report = agent_reports[uuid]

                enroll_agent(uuid, report)
                time.sleep(1)

            with agent_reports_lock:
                for uuid in list(agent_reports):
                    if uuid in enrolled:
                        del agent_reports[uuid]

        except Exception:
            log.exception("Unexpected error in poll loop")

        for _ in range(POLL_INTERVAL):
            if not running:
                break
            time.sleep(1)

    https_server.shutdown()
    log.info("Auto-enrollment daemon stopped")


if __name__ == "__main__":
    main()
