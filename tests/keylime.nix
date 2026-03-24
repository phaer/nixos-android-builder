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

      environment.systemPackages = [
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

      # imageModules sets system.name = "android-builder"; restore the node name
      # so the test driver exposes it as `agent`, not `android_builder`
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
        pkgs.tpm2-tools
        (pkgs.callPackage ../packages/measured-boot-state { }).measure-boot-state
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
    '';
}
