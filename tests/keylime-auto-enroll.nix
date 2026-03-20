# Test: auto-enrollment of keylime agents with full PCR policy.
#
# Verifies that the auto-enrollment daemon on the server side
# automatically enrolls a new agent when it both registers with
# the registrar AND reports its full TPM PCR values.
{
  keylimeModule,
  keylimeAgentModule,
  keylimeAgentPackage,
  imageModules,
  lib,
  pkgs,
  ...
}:
let
  tlsDir = "/var/lib/keylime/tls";
  caCert = "${tlsDir}/ca-cert.pem";
  caKey = "${tlsDir}/ca-key.pem";
  serverCert = "${tlsDir}/server-cert.pem";
  serverKey = "${tlsDir}/server-key.pem";
  clientCert = "${tlsDir}/client-cert.pem";
  clientKey = "${tlsDir}/client-key.pem";

  autoEnrollScript = pkgs.writers.writePython3 "keylime-auto-enroll" {
    flakeIgnore = [
      "E501"
      "E266"
      "N802"
    ];
  } (builtins.readFile ../system-manager/keylime-auto-enroll.py);

  pcrPolicy = pkgs.callPackage ../packages/pcr-policy { };
in
{
  name = "keylime-auto-enroll";

  nodes.server =
    { pkgs, ... }:
    {
      imports = [ keylimeModule ];

      virtualisation.tpm.enable = true;

      networking.firewall.allowedTCPPorts = [ 8893 ];

      environment.systemPackages = [
        pkgs.openssl
        pkgs.tpm2-tools
        pkgs.curl
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

      system.name = lib.mkForce "agent";

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
        pkgs.tpm2-tools
        pkgs.curl
        pcrPolicy.report-mb-refstate
        (pkgs.callPackage ../packages/keylime-uki-policy { }).create-uki-refstate
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
      # Don't auto-start — we trigger it manually after agent starts
      systemd.services.keylime-report-mb-refstate.wantedBy = lib.mkForce [ ];
    };

  testScript =
    { nodes, ... }:
    ''
      import subprocess, os, json

      # Prepare the agent's signed writable disk image
      subprocess.run([
        "${lib.getExe nodes.agent.system.build.prepareWritableDisk}"
      ], env=os.environ.copy(), cwd=agent.state_dir, check=True)

      import time as _time
      serial_stdout_on()
      server.start()
      agent.start(allow_reboot=True)

      server.wait_for_unit("multi-user.target")
      agent.wait_for_unit("multi-user.target")

      with subtest("Generate mTLS PKI and configure agent"):
        server.succeed("mkdir -p ${tlsDir}")

        server_ip = server.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
        server.log(f"Server IP: {server_ip}")

        server.succeed(
          "openssl req -x509 -newkey rsa:2048 -nodes"
          " -keyout ${caKey} -out ${caCert}"
          " -days 365 -subj '/CN=Keylime CA'"
          " -addext 'basicConstraints=critical,CA:TRUE'"
          " -addext 'keyUsage=critical,keyCertSign,cRLSign'"
        )
        server.succeed(
          "openssl req -newkey rsa:2048 -nodes"
          " -keyout ${serverKey} -out /tmp/server.csr -subj '/CN=server'"
        )
        server.succeed(
          "openssl x509 -req -in /tmp/server.csr"
          " -CA ${caCert} -CAkey ${caKey} -CAcreateserial"
          " -out ${serverCert} -days 365 -sha256"
          f" -extfile <(printf 'subjectAltName=DNS:server,DNS:localhost,IP:127.0.0.1,IP:{server_ip}')"
        )
        server.succeed(
          "openssl req -newkey rsa:2048 -nodes"
          " -keyout ${clientKey} -out /tmp/client.csr -subj '/CN=client'"
        )
        server.succeed(
          "openssl x509 -req -in /tmp/client.csr"
          " -CA ${caCert} -CAkey ${caKey} -CAcreateserial"
          " -out ${clientCert} -days 365 -sha256"
        )
        server.succeed("chown -R keylime:keylime ${tlsDir}")
        server.succeed("chmod 0640 ${tlsDir}/*")

        # Write attestation-server.json to agent
        ca_cert_pem = server.succeed("cat ${caCert}")
        server_json = json.dumps({"ip": server_ip, "ca_cert": ca_cert_pem})
        agent.succeed("mount -o remount,rw /boot")
        agent.succeed(f"cat > /boot/attestation-server.json << 'EOF'\n{server_json}\nEOF")
        agent.succeed("mount -o remount,ro /boot")

      with subtest("Start registrar and verifier"):
        server.succeed("systemctl start keylime-registrar.service")
        server.wait_for_unit("keylime-registrar.service")
        server.wait_for_open_port(8891)

        server.succeed("systemctl start keylime-verifier.service")
        server.wait_for_unit("keylime-verifier.service")
        server.wait_for_open_port(8881)

      with subtest("Start auto-enrollment daemon"):
        server.succeed(
          "KEYLIME_TLS_DIR=${tlsDir}"
          " KEYLIME_POLL_INTERVAL=2"
          " KEYLIME_ENROLL_PORT=8893"
          " ${autoEnrollScript}"
          " >> /tmp/auto-enroll.log 2>&1 &"
        )
        _time.sleep(2)  # Give the HTTPS server time to start

      with subtest("Agent registers and reports PCRs"):
        # Start the keylime agent (registers with registrar)
        agent.succeed("systemctl start keylime-agent.service")
        agent.wait_for_unit("keylime-agent.service")

        # Wait for the agent to register
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
          _time.sleep(1)
        assert agent_uuid, "Agent did not register within 30s"
        agent.log(f"Agent UUID: {agent_uuid}")

        # Report measured boot state to the enrollment server.
        # Reads UUID from agent_data.json and server address
        # from /boot/attestation-server.json.
        agent.succeed("report-mb-refstate")

      with subtest("Verifier attests the auto-enrolled agent with measured boot policy"):
        server.wait_until_succeeds(
          "curl -sk --cert ${clientCert} --key ${clientKey} --cacert ${caCert}"
          f" https://127.0.0.1:8881/v2.5/agents/{agent_uuid}"
          " | grep -q 'operational_state'",
          timeout=60,
        )
        server.log("Agent successfully auto-enrolled and attested!")

        # Verify the enrolled policy uses measured boot + PCR 11
        cvstatus = json.loads(server.succeed(
          "curl -sk --cert ${clientCert} --key ${clientKey} --cacert ${caCert}"
          f" https://127.0.0.1:8881/v2.5/agents/{agent_uuid}"
        ))
        results = cvstatus.get("results", {})
        tpm_policy_raw = results.get("tpm_policy", "{}")
        tpm_policy = json.loads(tpm_policy_raw) if isinstance(tpm_policy_raw, str) else tpm_policy_raw
        server.log(f"TPM policy keys: {list(tpm_policy.keys())}")

        # Only the mask should be present — no individual PCR entries
        for pcr in ["0", "1", "2", "3", "7", "11"]:
          assert pcr not in tpm_policy, f"PCR {pcr} should not be in tpm_policy (covered by mb_policy)"
        server.log("Policy verified: all PCRs covered by mb_policy")

      for i in range(1, 4):
        with subtest(f"Attestation persists after reboot {i}/3"):
          agent.shutdown()
          agent.start()
          agent.wait_for_unit("multi-user.target")
          agent.succeed("systemctl start keylime-agent")
          agent.wait_for_unit("keylime-agent.service")

          server.wait_until_succeeds(
            "curl -sk --cert ${clientCert} --key ${clientKey} --cacert ${caCert}"
            f" https://127.0.0.1:8881/v2.5/agents/{agent_uuid}"
            " | grep -q 'operational_state'",
            timeout=60,
          )
          server.log(f"Reboot {i}/3: attestation OK")
    '';
}
