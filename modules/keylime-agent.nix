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

  # Defaults for the push model agent (keylime_push_model_agent).
  # Only settings read by the push model are included.
  agentDefaults = {
    version = "2.4";
    uuid = "hash_ek";
    contact_ip = "127.0.0.1";
    contact_port = 9002;
    registrar_ip = "127.0.0.1";
    registrar_port = 8891;
    registrar_tls_enabled = true;
    registrar_tls_ca_cert = "/etc/keylime/registrar-ca.pem";
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
    verifier_tls_ca_cert = "/etc/keylime/registrar-ca.pem";
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

    registrar = {
      caCertFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to the CA certificate used to verify the registrar and
          verifier TLS connections.  When set, the file is copied into
          the image at `/etc/keylime/registrar-ca.pem` and the agent
          is configured to use it for both registrar and verifier TLS.
        '';
        example = lib.literalExpression "./keylime-ca.pem";
      };
    };

    settings = lib.mkOption {
      type = settingsType;
      default = { };
      description = ''
        Freeform settings for `agent.conf` under the `[agent]` section.
        Keys should use snake_case INI names matching the Rust keylime-agent config.
        Values are merged over built-in defaults (rust-keylime v0.2.9).
      '';
      example = {
        registrar_ip = "10.0.0.1";
        registrar_tls_enabled = true;
        registrar_tls_ca_cert = "/etc/keylime/ca-cert.pem";
        verifier_url = "https://10.0.0.1:8881";
        verifier_tls_ca_cert = "/etc/keylime/ca-cert.pem";
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
    ];

    security.tpm2 = {
      enable = true;
      tctiEnvironment.enable = true;
    };

    environment.etc = {
      "keylime/agent.conf" = {
        text = agentConf;
        user = "keylime";
        group = "keylime";
        mode = "0440";
      };
    }
    // lib.optionalAttrs (cfg.registrar.caCertFile != null) {
      "keylime/registrar-ca.pem" = {
        source = cfg.registrar.caCertFile;
        user = "keylime";
        group = "keylime";
        mode = "0444";
      };
    };

    systemd.services.keylime-agent = {
      description = "Keylime Push Model Agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/dev/tpm0";
      environment = {
        RUST_LOG = cfg.logLevel;
        KEYLIME_AGENT_CONFIG = "/etc/keylime/agent.conf";
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/keylime_push_model_agent";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
