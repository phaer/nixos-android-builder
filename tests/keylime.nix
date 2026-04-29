{
  keylimeModule,
  keylimeAgentModule,
  keylimeAgentPackage,
  customPackages,
  imageModules,
  lib,
  pkgs,
  ...
}:
let
  inherit (customPackages) tpm2-tools measuredBoot;
  # TLS certificate paths (populated by test script before services start)
  tlsDir = "/var/lib/keylime/tls";
  caCert = "${tlsDir}/ca-cert.pem";
  caKey = "${tlsDir}/ca-key.pem";
  serverCert = "${tlsDir}/server-cert.pem";
  serverKey = "${tlsDir}/server-key.pem";
  clientCert = "${tlsDir}/client-cert.pem";
  clientKey = "${tlsDir}/client-key.pem";
in
{
  name = "keylime";

  nodes.server =
    { pkgs, ... }:
    {
      imports = [ keylimeModule ];
      _module.args = { inherit customPackages; };

      virtualisation.tpm.enable = true;

      environment.systemPackages = [
        pkgs.openssl
        pkgs.sqlite
        tpm2-tools
      ];

      services.keylime = {
        enable = true;
        logLevel = "DEBUG";

        registrar = {
          enable = true;
          settings = {
            tls_dir = tlsDir;
            server_key = serverKey;
            server_cert = serverCert;
            trusted_client_ca = [ caCert ];
          };
        };

        verifier = {
          enable = true;
          settings = {
            mode = "push";
            enable_agent_mtls = true;
            tls_dir = tlsDir;
            server_key = serverKey;
            server_cert = serverCert;
            trusted_client_ca = [ caCert ];
            client_key = clientKey;
            client_cert = clientCert;
            trusted_server_ca = [ caCert ];
          };
        };
      };

      services.keylime.tenant.settings = {
        tls_dir = tlsDir;
        client_key = clientKey;
        client_cert = clientCert;
        trusted_server_ca = [ caCert ];
      };

      # Don't start keylime services automatically — start after cert provisioning
      systemd.services.keylime-registrar.wantedBy = lib.mkForce [ ];
      systemd.services.keylime-verifier.wantedBy = lib.mkForce [ ];
    };

  nodes.agent =
    { config, lib, ... }:
    {
      imports = imageModules ++ [ keylimeAgentModule ];
      _module.args = { inherit customPackages; };

      # imageModules sets system.name = "android-builder"; override it so the
      # test driver exposes this machine as `agent` (it uses system.name for
      # Python variable names). nixosAndroidBuilder.imageId stays at its
      # default "android-builder" so configure-disk-image commands accept it.
      system.name = lib.mkForce "agent";

      # Reduce resource usage — we don't need the full android builder footprint
      virtualisation = lib.mkVMOverride {
        diskSize = 8 * 1024;
        memorySize = 2 * 1024;
        cores = 2;
      };
      systemd.repart.partitions."40-var-lib-build".SizeMinBytes = lib.mkVMOverride "1G";

      nixosAndroidBuilder.unattended.enable = lib.mkForce false;

      environment.systemPackages = [
        pkgs.coreutils
        pkgs.openssl
        tpm2-tools
        measuredBoot.measure-boot-state
      ];

      systemd.tmpfiles.rules = [
        "d ${tlsDir} 0750 keylime keylime -"
      ];

      services.keylime-agent = {
        enable = true;
        settings = {
          contact_ip = lib.mkForce "192.168.1.1";
          attestation_interval_seconds = lib.mkForce 2;
        };
      };

      # Don't start automatically — start after CA cert is provisioned
      systemd.services.keylime-agent.wantedBy = lib.mkForce [ ];
    };

  testScript =
    { nodes, ... }:
    ''
      import subprocess, os, json, time

      # Prepare the agent's signed writable disk image (like the integration test)
      subprocess.run([
        "${lib.getExe nodes.agent.system.build.prepareWritableDisk}"
      ], env=os.environ.copy(), cwd=agent.state_dir, check=True)

      serial_stdout_on()
      server.start()
      agent.start(allow_reboot=True)

      server.wait_for_unit("multi-user.target")
      # Agent reboots once to enroll Secure Boot keys; wait for the second boot
      agent.wait_for_unit("multi-user.target")
      with subtest("Generate mTLS PKI on server and configure agent via attestation-server.json"):
        server.succeed("mkdir -p ${tlsDir}")

        # Discover server IP on the test vlan (eth1)
        server_ip = server.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
        server.log(f"Server IP: {server_ip}")

        server.succeed(
          "openssl req -x509 -newkey rsa:2048 -nodes"
          " -keyout ${caKey}"
          " -out ${caCert}"
          " -days 365"
          " -subj '/CN=Keylime CA'"
          " -addext 'basicConstraints=critical,CA:TRUE'"
          " -addext 'keyUsage=critical,keyCertSign,cRLSign'"
        )

        server.succeed(
          "openssl req -newkey rsa:2048 -nodes"
          " -keyout ${serverKey}"
          " -out /tmp/server.csr"
          " -subj '/CN=server'"
        )
        server.succeed(
          "openssl x509 -req"
          " -in /tmp/server.csr"
          " -CA ${caCert}"
          " -CAkey ${caKey}"
          " -CAcreateserial"
          " -out ${serverCert}"
          " -days 365 -sha256"
          f" -extfile <(printf 'subjectAltName=DNS:server,DNS:localhost,IP:127.0.0.1,IP:{server_ip}')"
        )

        server.succeed(
          "openssl req -newkey rsa:2048 -nodes"
          " -keyout ${clientKey}"
          " -out /tmp/client.csr"
          " -subj '/CN=client'"
        )
        server.succeed(
          "openssl x509 -req"
          " -in /tmp/client.csr"
          " -CA ${caCert}"
          " -CAkey ${caKey}"
          " -CAcreateserial"
          " -out ${clientCert}"
          " -days 365 -sha256"
        )

        server.succeed("chown -R keylime:keylime ${tlsDir}")
        server.succeed("chmod 0640 ${tlsDir}/*")

        server.succeed("openssl verify -CAfile ${caCert} ${serverCert}")
        server.succeed("openssl verify -CAfile ${caCert} ${clientCert}")

        # Write attestation-server.json to /boot on the agent (replaces build-time config)
        ca_cert_pem = server.succeed("cat ${caCert}")
        server_json = json.dumps({"ip": server_ip, "ca_cert": ca_cert_pem})
        agent.succeed("mount -o remount,rw /boot")
        agent.succeed(f"cat > /boot/attestation-server.json << 'EOF'\n{server_json}\nEOF")
        agent.succeed("mount -o remount,ro /boot")

      with subtest("Registrar starts and is listening with TLS"):
        server.succeed("systemctl start keylime-registrar.service")
        server.wait_for_unit("keylime-registrar.service")
        server.wait_for_open_port(8891)

      with subtest("Verifier starts and is listening with mTLS"):
        server.succeed("systemctl start keylime-verifier.service")
        server.wait_for_unit("keylime-verifier.service")
        server.wait_for_open_port(8881)

      with subtest("Agent starts and registers (EK-derived UUID)"):
        agent.succeed("systemctl start keylime-agent.service")
        agent.wait_for_unit("keylime-agent.service")

        # Discover the EK-derived UUID from the registrar API.
        # Registration is async, so retry until the agent appears.
        agent_uuid = None
        for _ in range(30):
          resp = json.loads(server.succeed(
            "curl -sk --cert ${clientCert} --key ${clientKey} --cacert ${caCert}"
            " https://127.0.0.1:8891/v2.5/agents/"
          ))
          uuids = resp.get("results", {}).get("uuids", [])
          if uuids:
            agent_uuid = uuids[0]
            break
          time.sleep(1)
        assert agent_uuid, "Agent did not register within 30s"
        agent.log(f"Agent EK-derived UUID: {agent_uuid}")

      with subtest("Agent can be added for attestation with measured boot policy"):
        # Generate measured boot reference state from the UEFI event log
        agent.succeed(
          "measure-boot-state"
          " -e /sys/kernel/security/tpm0/binary_bios_measurements"
          " -o /tmp/measured-boot-state.json"
        )
        # Copy refstate to server for enrollment
        measured_boot_state = agent.succeed("cat /tmp/measured-boot-state.json")
        server.succeed(f"cat > /tmp/measured-boot-state.json << 'REFSTATE_EOF'\n{measured_boot_state}\nREFSTATE_EOF")

        server.succeed(
          f"keylime_tenant --push-model -c add -t 192.168.1.1 -u {agent_uuid}"
          " -r 127.0.0.1 -rp 8891 -v 127.0.0.1 -vp 8881"
          " --mb_refstate /tmp/measured-boot-state.json"
        )

      with subtest("Verifier attests the agent (reaches Get Quote state)"):
        server.wait_until_succeeds(
          f"keylime_tenant -c cvstatus -u {agent_uuid} -v 127.0.0.1 -vp 8881 > /tmp/cvstatus.out 2>&1"
          " && grep -qE '\"operational_state\": \"(Get Quote|Provide V)\"' /tmp/cvstatus.out",
          timeout=60,
        )

      with subtest("Tampered refstate is rejected (wrong UKI digest)"):
        # Tamper the UKI digest in the refstate
        tampered_state = json.loads(measured_boot_state)
        tampered_state["uki_digest"] = {"sha256": "0x" + "00" * 32}
        tampered_json = json.dumps(tampered_state)
        server.succeed(f"cat > /tmp/tampered-state.json << 'TAMPERED_EOF'\n{tampered_json}\nTAMPERED_EOF")

        # Delete and re-add with the tampered refstate.  The agent
        # keeps running — its UEFI event log bytes are cached in
        # memory, so it can still provide attestation evidence after
        # the delete.
        server.succeed(
          f"keylime_tenant -c delete -u {agent_uuid}"
          " -v 127.0.0.1 -vp 8881"
        )
        server.succeed(
          f"keylime_tenant --push-model -c add -t 192.168.1.1 -u {agent_uuid}"
          " -r 127.0.0.1 -rp 8891 -v 127.0.0.1 -vp 8881"
          " --mb_refstate /tmp/tampered-state.json"
        )

        # The verifier evaluates the agent's evidence against the
        # tampered refstate and rejects it due to UKI digest mismatch.
        server.wait_until_succeeds(
          "journalctl -u keylime-verifier --no-pager"
          " | grep -q 'failed verification due to policy violations'",
          timeout=90,
        )
        server.log("Tampered UKI digest correctly rejected")

      with subtest("Push-mode agent recovers from timeout"):
        # Helper to fetch the verifier's view of the agent.
        def get_agent_results():
          resp = json.loads(server.succeed(
            "curl -sk --cert ${clientCert} --key ${clientKey} --cacert ${caCert}"
            f" https://127.0.0.1:8881/v2.5/agents/{agent_uuid}"
          ))
          return resp.get("results", {})

        def get_attestation_status():
          return get_agent_results().get("attestation_status", "")

        def dump_state(label):
          r = get_agent_results()
          server.log(
            f"{label}: status={r.get('attestation_status')}"
            f" accept={r.get('accept_attestations')}"
            f" count={r.get('attestation_count')}"
            f" failures={r.get('consecutive_attestation_failures')}"
            f" last_quote={r.get('last_received_quote')}"
            f" last_ok={r.get('last_successful_attestation')}"
          )

        # Re-enroll with the correct refstate so we're back in PASS state.
        server.succeed(
          f"keylime_tenant -c delete -u {agent_uuid}"
          " -v 127.0.0.1 -vp 8881"
        )
        server.succeed(
          f"keylime_tenant --push-model -c add -t 192.168.1.1 -u {agent_uuid}"
          " -r 127.0.0.1 -rp 8891 -v 127.0.0.1 -vp 8881"
          " --mb_refstate /tmp/measured-boot-state.json"
        )

        for _ in range(60):
          if get_attestation_status() == "PASS":
            break
          time.sleep(1)
        dump_state("after re-enrollment")
        assert get_attestation_status() == "PASS", "agent did not return to PASS after re-enrollment"
        baseline = get_agent_results()
        baseline_count = baseline.get("attestation_count") or 0
        server.log("Agent back in PASS state; stopping to trigger timeout")

        # Stop the agent to simulate silence.  With quote_interval=2
        # and the upstream 5x multiplier, push_agent_monitor will
        # mark accept_attestations=False after ~10s.
        agent.succeed("systemctl stop keylime-agent.service")

        for _ in range(30):
          if get_attestation_status() == "FAIL":
            break
          time.sleep(1)
        dump_state("after timeout")
        assert get_attestation_status() == "FAIL", "verifier did not mark agent FAIL after timeout"
        server.log("Agent marked FAIL after push-mode timeout fired")

        # Restart the agent.  The verifier's attestation_controller
        # has an explicit bypass for push-mode agents, so a new
        # successful attestation should reset accept_attestations=True.
        agent.succeed("systemctl start keylime-agent.service")
        agent.wait_for_unit("keylime-agent.service")
        restart_time = time.time()

        # Recovery requires the agent to push at least one new
        # successful attestation.  We watch attestation_count, not
        # just status — a stale PASS reading should not pass.
        recovered = False
        for _ in range(120):
          r = get_agent_results()
          new_count = r.get("attestation_count") or 0
          if r.get("attestation_status") == "PASS" and new_count > baseline_count:
            recovered = True
            break
          time.sleep(1)

        if not recovered:
          dump_state("recovery FAILED — final state")
          # Dump the full verifier response to see all fields
          full_response = server.succeed(
            "curl -sk --cert ${clientCert} --key ${clientKey} --cacert ${caCert}"
            f" https://127.0.0.1:8881/v2.5/agents/{agent_uuid}"
          )
          server.log(f"full verifier response:\n{full_response}")
          # Query the SQLite database directly for the raw accept_attestations value
          db_value = server.succeed(
            "sqlite3 /var/lib/keylime/cv_data.sqlite"
            f" \"SELECT agent_id, accept_attestations, attestation_count,"
            " consecutive_attestation_failures FROM verifiermain"
            f" WHERE agent_id='{agent_uuid}';\" || true"
          )
          server.log(f"DB row: {db_value}")
          server.log(
            "agent journal since restart:\n"
            + agent.succeed(
              f"journalctl -u keylime-agent.service --since='@{int(restart_time)}'"
              " --no-pager -o cat || true"
            )
          )
          server.log(
            "verifier journal (grep accept):\n"
            + server.succeed("journalctl -u keylime-verifier.service --no-pager -o cat | grep -i 'accept_attest\\|push_agent_monitor\\|attestation.*passed' | tail -40 || true")
          )
        assert recovered, "agent did not recover from timeout"
        server.log("Agent recovered to PASS — push-mode self-healing works")
    '';
}
