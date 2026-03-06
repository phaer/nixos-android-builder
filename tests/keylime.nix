{
  keylimeModule,
  keylimeAgentModule,
  keylimeAgentPackage,
  keylimePackage,
  imageModules,
  lib,
  pkgs,
  ...
}:
let
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

      virtualisation.tpm.enable = true;

      networking.firewall.allowedTCPPorts = [
        8881
        8890
        8891
      ];

      environment.systemPackages = [
        keylimePackage
        pkgs.openssl
        pkgs.tpm2-tools
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

      # Tenant configuration (runs on the server node to enroll agents)
      environment.etc."keylime/tenant.conf" = {
        text = ''
          [tenant]
          version = 2.5
          verifier_ip = 127.0.0.1
          verifier_port = 8881
          registrar_ip = 127.0.0.1
          registrar_port = 8891
          tls_dir = ${tlsDir}
          enable_agent_mtls = True
          client_key = ${clientKey}
          client_key_password =
          client_cert = ${clientCert}
          trusted_server_ca = ["${caCert}"]
          agent_mtls_cert = default
          tpm_cert_store = /var/lib/keylime/tpm_cert_store
          max_payload_size = 1048576
          accept_tpm_hash_algs = ["sha512", "sha384", "sha256"]
          accept_tpm_encryption_algs = ["ecc", "rsa"]
          accept_tpm_signing_algs = ["ecschnorr", "rsassa", "rsapss", "ecdsa", "ecdaa"]
          exponential_backoff = False
          retry_interval = 2
          max_retries = 5
          request_timeout = 60
          require_ek_cert = False
          ek_check_script =
          mb_refstate =
        '';
        user = "keylime";
        group = "keylime";
        mode = "0440";
      };

      # Don't start keylime services automatically — start after cert provisioning
      systemd.services.keylime-registrar.wantedBy = lib.mkForce [ ];
      systemd.services.keylime-verifier.wantedBy = lib.mkForce [ ];
    };

  nodes.agent =
    { config, lib, ... }:
    {
      imports = imageModules ++ [ keylimeAgentModule ];

      # imageModules sets system.name = "android-builder"; restore the node name
      # so the test driver exposes it as `agent`, not `android_builder`
      system.name = lib.mkForce "agent";

      # Reduce resource usage — we don't need the full android builder footprint
      virtualisation = lib.mkVMOverride {
        diskSize = 8 * 1024;
        memorySize = 2 * 1024;
        cores = 2;
      };
      systemd.repart.partitions."30-var-lib-build".SizeMinBytes = lib.mkVMOverride "1G";

      nixosAndroidBuilder.unattended.enable = lib.mkForce false;

      environment.systemPackages = [
        pkgs.coreutils
        pkgs.openssl
        pkgs.tpm2-tools
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
      import subprocess, os, json

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
        server.wait_for_open_port(8890)
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
          import time; time.sleep(1)
        assert agent_uuid, "Agent did not register within 30s"
        agent.log(f"Agent EK-derived UUID: {agent_uuid}")

      with subtest("Read and verify PCRs from agent TPM"):
        # read-firmware-pcrs reads PCRs 0-3, 7 from the TPM.
        # --verify-pcr11 also reads PCR 11 and checks it against the
        # expected value baked into the ESP at /boot/expected-pcr11.
        tpm_policy_str = agent.succeed("read-firmware-pcrs --verify-pcr11")
        tpm_policy = json.loads(tpm_policy_str)
        for pcr in ("0", "1", "2", "3", "7", "11"):
          agent.log(f"PCR{pcr} = {tpm_policy[pcr][0]}")
        pcr7 = tpm_policy["7"][0]
        assert len(pcr7) == 64, f"unexpected PCR7 length: {len(pcr7)}"
        assert pcr7 != "0" * 64, "PCR7 is all zeros — Secure Boot not active?"

      with subtest("Agent can be added for attestation with PCR policy"):
        # Use the verified policy from read-firmware-pcrs directly.
        # --push-model skips contacting the agent (no listening port in push mode).
        policy = json.dumps({"7": tpm_policy["7"], "11": tpm_policy["11"]})
        server.succeed(
          f"keylime_tenant --push-model -c add -t 192.168.1.1 -u {agent_uuid}"
          " -r 127.0.0.1 -rp 8891 -v 127.0.0.1 -vp 8881"
          f" --tpm_policy '{policy}'"
        )

      with subtest("Verifier attests the agent (reaches Get Quote state)"):
        server.wait_until_succeeds(
          f"keylime_tenant -c cvstatus -u {agent_uuid} -v 127.0.0.1 -vp 8881 > /tmp/cvstatus.out 2>&1"
          " && grep -qE '\"operational_state\": \"(Get Quote|Provide V)\"' /tmp/cvstatus.out",
          timeout=60,
        )
    '';
}
