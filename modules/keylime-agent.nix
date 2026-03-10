{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.keylime-agent;

  keylimeAgentPkg = pkgs.callPackage ../packages/keylime-agent { };

  # The Rust keylime-agent uses TOML, so string values must be quoted.
  mkValueString =
    v:
    if builtins.isList v then
      "[${lib.concatMapStringsSep ", " (s: ''"${s}"'') v}]"
    else if builtins.isBool v then
      (if v then "true" else "false")
    else if builtins.isInt v then
      toString v
    else if builtins.isString v then
      ''"${v}"''
    else
      throw "unsupported TOML value type: ${builtins.typeOf v}";

  toTOML = lib.generators.toINI {
    mkKeyValue = lib.generators.mkKeyValueDefault { inherit mkValueString; } " = ";
  };

  # Path where the runtime config is generated from /boot/attestation-server.json.
  runtimeConf = "/run/keylime/agent.conf";
  runtimeCaCert = "/run/keylime/ca-cert.pem";

  # Agent state (AK) persisted here across reboots.
  persistDir = "/boot/keylime";

  # Defaults for the push model agent (keylime_push_model_agent).
  # Only settings read by the push model are included.
  # registrar_ip, verifier_url, and CA cert paths are placeholders —
  # they are overridden at boot from /boot/attestation-server.json.
  agentDefaults = {
    version = "2.4";
    uuid = "hash_ek";
    contact_ip = "127.0.0.1";
    contact_port = 9002;
    registrar_ip = "127.0.0.1";
    registrar_port = 8891;
    registrar_tls_enabled = true;
    registrar_tls_ca_cert = runtimeCaCert;
    registrar_api_versions = "default";
    keylime_dir = "/var/lib/keylime";
    exponential_backoff_initial_delay = 10000;
    exponential_backoff_max_retries = 5;
    exponential_backoff_max_delay = 300000;
    tpm_hash_alg = "sha256";
    tpm_encryption_alg = "rsa";
    tpm_signing_alg = "rsassa";
    ek_handle = "generate";
    enable_iak_idevid = false;
    run_as = "keylime:tss";
    agent_data_path = "default";
    ima_ml_path = "default";
    measuredboot_ml_path = "default";
    attestation_interval_seconds = 60;
    verifier_url = "https://localhost:8881";
    verifier_tls_ca_cert = runtimeCaCert;
    certification_keys_server_identifier = "ak";
    uefi_logs_evidence_version = "2.1";
    tls_accept_invalid_certs = false;
    tls_accept_invalid_hostnames = false;
  };

  agentConf = toTOML {
    agent = agentDefaults // cfg.settings;
  };

  settingsType = lib.types.attrsOf (
    lib.types.oneOf [
      lib.types.str
      lib.types.int
      lib.types.bool
      (lib.types.listOf lib.types.str)
    ]
  );

  # Reads /boot/attestation-server.json at boot, extracts the CA cert,
  # and patches the agent config with the server IP and ports.
  configureAgent =
    pkgs.writers.writePython3 "keylime-configure-agent"
      {
        flakeIgnore = [ "E501" ];
      }
      ''
        import json
        import os
        import pwd
        import grp
        import re
        import shutil
        import sys

        SRC = "/boot/attestation-server.json"
        BUILD_CONF = "/etc/keylime/agent.conf"
        RUNTIME_CONF = "${runtimeConf}"
        CA_CERT = "${runtimeCaCert}"


        def owner():
            uid = pwd.getpwnam("keylime").pw_uid
            gid = grp.getgrnam("keylime").gr_gid
            return uid, gid


        uid, gid = owner()

        if not os.path.exists(SRC):
            sys.exit(f"Error: {SRC} not found. Run 'configure-disk-image set-attestation-server' first.")

        with open(SRC) as f:
            data = json.load(f)

        ip = data.get("ip")
        ca_cert = data.get("ca_cert")
        port = data.get("port", 8891)
        vport = data.get("verifier_port", 8881)

        if not ip:
            sys.exit("Error: attestation-server.json missing 'ip'")
        if not ca_cert:
            sys.exit("Error: attestation-server.json missing 'ca_cert'")

        with open(CA_CERT, "w") as f:
            f.write(ca_cert if ca_cert.endswith("\n") else ca_cert + "\n")
        os.chown(CA_CERT, uid, gid)
        os.chmod(CA_CERT, 0o440)

        with open(BUILD_CONF) as f:
            conf = f.read()

        for key, val in [
            ("registrar_ip", f'"{ip}"'),
            ("registrar_port", str(port)),
            ("verifier_url", f'"https://{ip}:{vport}"'),
        ]:
            conf = re.sub(
                rf"^{key} = .*$", f"{key} = {val}",
                conf, flags=re.M,
            )

        with open(RUNTIME_CONF, "w") as f:
            f.write(conf)
        os.chown(RUNTIME_CONF, uid, gid)
        os.chmod(RUNTIME_CONF, 0o440)

        print(f"Configured: registrar={ip}:{port} verifier=https://{ip}:{vport}")

        # Restore persisted AK from /boot. /var/lib is ephemeral, so without
        # this the agent creates a new AK on every boot and the registrar
        # rejects re-registration.
        PERSIST = "${persistDir}"
        WORK = "/var/lib/keylime"
        if os.path.isdir(PERSIST):
            for name in os.listdir(PERSIST):
                src = os.path.join(PERSIST, name)
                dst = os.path.join(WORK, name)
                if os.path.isfile(src):
                    shutil.copy2(src, dst)
                    os.chown(dst, uid, gid)
            print(f"Restored agent state from {PERSIST}")
        else:
            print(f"No persisted state at {PERSIST}")
      '';

  # Persist agent AK to /boot after the file appears so it survives reboots.
  # Triggered by keylime-persist-agent.path (PathExists watch).
  persistAgent = pkgs.writeShellScript "keylime-persist-agent" ''
    set -euo pipefail
    src=/var/lib/keylime/agent_data.json
    dst=${persistDir}
    [ -f "$src" ] || { echo "$src not found, skipping"; exit 0; }
    ${pkgs.util-linux}/bin/mount -o remount,rw /boot
    mkdir -p "$dst"
    cp "$src" "$dst"/
    ${pkgs.util-linux}/bin/mount -o remount,ro /boot
    echo "Persisted agent AK to $dst"
  '';

in
{
  options.services.keylime-agent = {
    enable = lib.mkEnableOption "Keylime push model agent for TPM-based remote attestation";

    package = lib.mkOption {
      type = lib.types.package;
      default = keylimeAgentPkg;
      description = "The keylime-agent (Rust) package to use.";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "keylime_push_model_agent=info,keylime=info";
      description = ''
        RUST_LOG filter string for the agent.
        For example `"keylime_agent=debug,keylime=info"`.
      '';
    };

    settings = lib.mkOption {
      type = settingsType;
      default = { };
      description = ''
        Freeform settings for `agent.conf` under the `[agent]` section.
        Keys should use snake_case INI names matching the Rust keylime-agent config.
        Values are merged over built-in defaults (rust-keylime v0.2.9).

        Note: `registrar_ip`, `verifier_url`, and CA cert paths are
        configured at boot from `/boot/attestation-server.json` (written by
        `configure-disk-image set-attestation-server`).  Build-time overrides
        here will be replaced at runtime if that file exists.
      '';
      example = {
        attestation_interval_seconds = 30;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.keylime = {
      isSystemUser = true;
      group = "keylime";
      home = "/var/lib/keylime";
      extraGroups = [ "tss" ];
    };

    users.groups.keylime = { };

    systemd.tmpfiles.rules = [
      "d /var/lib/keylime 0750 keylime keylime -"
      "d /run/keylime 0750 keylime keylime -"
    ];

    security.tpm2 = {
      enable = true;
      tctiEnvironment.enable = true;
    };

    environment.etc."keylime/agent.conf" = {
      text = agentConf;
      user = "keylime";
      group = "keylime";
      mode = "0440";
    };

    systemd.services.keylime-agent = {
      description = "Keylime Push Model Agent";
      after = [
        "network-online.target"
        "boot.mount"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/dev/tpm0";
      environment = {
        RUST_LOG = cfg.logLevel;
        KEYLIME_AGENT_CONFIG = runtimeConf;
      };
      serviceConfig = {
        ExecStartPre = "${configureAgent}";
        ExecStart = "${cfg.package}/bin/keylime_push_model_agent";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Watch for agent_data.json and persist it to /boot once it appears.
    systemd.paths.keylime-persist-agent = {
      description = "Watch for Keylime agent data to persist";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = "/var/lib/keylime/agent_data.json";
        Unit = "keylime-persist-agent.service";
      };
    };

    systemd.services.keylime-persist-agent = {
      description = "Persist Keylime agent AK to /boot";
      after = [ "boot.mount" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${persistAgent}";
      };
    };
  };
}
