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
  agentUuid = "d432fbb3-d2f1-4a97-9ef7-75bd81c00000";

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
            ip = "0.0.0.0";
            tls_dir = tlsDir;
            server_key = serverKey;
            server_cert = serverCert;
            trusted_client_ca = [ caCert ];
          };
        };

        verifier = {
          enable = true;
          settings = {
            ip = "0.0.0.0";
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

      networking.firewall.allowedTCPPorts = [ 9002 ];

      environment.systemPackages = [
        pkgs.openssl
        pkgs.tpm2-tools
      ];

      systemd.tmpfiles.rules = [
        "d ${tlsDir} 0750 keylime keylime -"
      ];

      services.keylime-agent = {
        enable = true;
        settings = {
          uuid = agentUuid;
          ip = "0.0.0.0";
          port = 9002;
          contact_ip = "192.168.1.1";
          contact_port = 9002;
          registrar_ip = "server";
          registrar_port = 8890;
          registrar_tls_enabled = true;
          registrar_tls_ca_cert = caCert;
          enable_agent_mtls = true;
          enable_insecure_payload = true;
          trusted_client_ca = caCert;
          enable_revocation_notifications = false;
          run_as = "";
        };
      };

      # Don't start automatically — start after CA cert is provisioned
      systemd.services.keylime-agent.wantedBy = lib.mkForce [ ];
    };

  testScript =
    { nodes, ... }:
    let
      # Pre-calculate the PCR11 value that the agent will have after a full boot.
      # systemd-stub measures each UKI PE section into PCR 11, then the stage-2
      # pcrphase services extend it with boot phase strings (sysinit, ready).
      # We extract sections from the built UKI with objcopy because the .cmdline
      # embeds a usrhash that is only known after the image is built, so we
      # cannot reconstruct it from NixOS module attributes alone.
      pcr11 = pkgs.runCommand "pcr11" {
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.jq
        ];
        systemdMeasure = "${pkgs.systemd}/lib/systemd/systemd-measure";
        uki = "${nodes.agent.system.build.uki}/${nodes.agent.system.build.uki.name}";
      } ''
        cp "$uki" uki.efi
        chmod 644 uki.efi
        for section in .linux .osrel .cmdline .initrd .uname .sbat; do
          name="''${section#.}"
          objcopy --dump-section "''${section}=''${name}" uki.efi 2>/dev/null || true
        done
        $systemdMeasure calculate \
          --linux=linux \
          $(test -f osrel   && echo --osrel=osrel)   \
          $(test -f cmdline && echo --cmdline=cmdline) \
          $(test -f initrd  && echo --initrd=initrd)  \
          $(test -f uname   && echo --uname=uname)    \
          $(test -f sbat    && echo --sbat=sbat)      \
          --phase=sysinit:ready \
          --bank=sha256 --json=short \
        | jq -jr '.sha256[0].hash' > $out
      '';
      pcr11hash = builtins.readFile pcr11;
      tpmPolicy = builtins.toJSON { "11" = [ pcr11hash ]; };
    in
    ''
    import subprocess, os

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

      with subtest("Generate mTLS PKI on server and distribute CA cert to agent"):
        server.succeed("mkdir -p ${tlsDir}")

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
          " -extfile <(printf 'subjectAltName=DNS:server,DNS:localhost,IP:127.0.0.1')"
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

        ca_cert = server.succeed("cat ${caCert}")
        agent.succeed(f"cat > ${caCert} << 'EOF'\n{ca_cert}EOF")
        agent.succeed("chown -R keylime:keylime ${tlsDir}")
        agent.succeed("chmod 0640 ${tlsDir}/*")

        server.succeed("openssl verify -CAfile ${caCert} ${serverCert}")
        server.succeed("openssl verify -CAfile ${caCert} ${clientCert}")

      with subtest("Registrar starts and is listening with TLS"):
        server.succeed("systemctl start keylime-registrar.service")
        server.wait_for_unit("keylime-registrar.service")
        server.wait_for_open_port(8890)
        server.wait_for_open_port(8891)

      with subtest("Verifier starts and is listening with mTLS"):
        server.succeed("systemctl start keylime-verifier.service")
        server.wait_for_unit("keylime-verifier.service")
        server.wait_for_open_port(8881)

      with subtest("Agent starts and registers with mTLS"):
        agent.succeed("systemctl start keylime-agent.service")
        agent.wait_for_unit("keylime-agent.service")
        agent.wait_for_open_port(9002)

      with subtest("Agent is registered in the registrar"):
        server.wait_until_succeeds(
          "keylime_tenant -c regstatus -u ${agentUuid} -r 127.0.0.1 -rp 8891 > /tmp/regstatus.out 2>&1"
          " && grep -q '\"${agentUuid}\"' /tmp/regstatus.out",
          timeout=30,
        )

    tpm_policy = '${tpmPolicy}'
    with subtest("Agent can be added for attestation with PCR11 policy"):
      server.succeed(
        "keylime_tenant -c add -t 192.168.1.1 -u ${agentUuid}"
          " -r 127.0.0.1 -rp 8891 -v 127.0.0.1 -vp 8881"
          f" --tpm_policy '{tpm_policy}'"
        )

      with subtest("Verifier attests the agent (reaches Get Quote state)"):
        server.wait_until_succeeds(
          "keylime_tenant -c cvstatus -u ${agentUuid} -v 127.0.0.1 -vp 8881 > /tmp/cvstatus.out 2>&1"
          " && grep -qE '\"operational_state\": \"(Get Quote|Provide V)\"' /tmp/cvstatus.out",
          timeout=60,
        )
    '';
}
