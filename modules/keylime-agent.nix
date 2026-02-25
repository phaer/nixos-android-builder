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

  # Upstream defaults from rust-keylime v0.2.9 keylime-agent.conf
  agentDefaults = {
    version = "2.4";
    api_versions = "default";
    uuid = "d432fbb3-d2f1-4a97-9ef7-75bd81c00000";
    ip = "127.0.0.1";
    port = 9002;
    contact_ip = "127.0.0.1";
    contact_port = 9002;
    registrar_ip = "127.0.0.1";
    registrar_port = 8890;
    registrar_tls_enabled = false;
    registrar_tls_ca_cert = "default";
    registrar_api_versions = "default";
    enable_agent_mtls = true;
    keylime_dir = "/var/lib/keylime";
    server_key = "default";
    server_key_password = "";
    payload_key = "default";
    payload_key_password = "";
    server_cert = "default";
    trusted_client_ca = "default";
    enc_keyname = "derived_tci_key";
    dec_payload_file = "decrypted_payload";
    secure_size = "1m";
    extract_payload_zip = true;
    enable_revocation_notifications = false;
    revocation_actions_dir = "/usr/libexec/keylime";
    revocation_notification_ip = "127.0.0.1";
    revocation_notification_port = 8992;
    revocation_cert = "default";
    revocation_actions = "";
    payload_script = "autorun.sh";
    enable_insecure_payload = false;
    allow_payload_revocation_actions = true;
    exponential_backoff_initial_delay = 10000;
    exponential_backoff_max_retries = 5;
    exponential_backoff_max_delay = 300000;
    tpm_hash_alg = "sha256";
    tpm_encryption_alg = "rsa";
    tpm_signing_alg = "rsassa";
    ek_handle = "generate";
    enable_iak_idevid = false;
    iak_idevid_template = "detect";
    iak_idevid_asymmetric_alg = "rsa";
    iak_idevid_name_alg = "sha256";
    idevid_password = "";
    idevid_handle = "";
    iak_password = "";
    iak_handle = "";
    iak_cert = "default";
    idevid_cert = "default";
    tpm_ownerpassword = "";
    run_as = "keylime:tss";
    agent_data_path = "default";
    ima_ml_path = "default";
    measuredboot_ml_path = "default";
    attestation_interval_seconds = 60;
    verifier_url = "https://localhost:8881";
    verifier_tls_ca_cert = "default";
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
    enable = lib.mkEnableOption "Keylime agent (Rust) for TPM-based remote attestation";

    package = lib.mkOption {
      type = lib.types.package;
      default = keylimeAgentPkg;
      description = "The keylime-agent (Rust) package to use.";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "keylime_agent=info,keylime=info";
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
          Path to the CA certificate used to verify the registrar's TLS
          connection.  When set, the file is copied into the image at
          `/etc/keylime/registrar-ca.pem` and the agent is automatically
          configured to use it for verify registrar and verify connections.
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
        uuid = "generate";
        ip = "0.0.0.0";
        port = 9002;
        contact_ip = "192.168.1.1";
        registrar_ip = "10.0.0.1";
        registrar_tls_enabled = true;
        registrar_tls_ca_cert = "/var/lib/keylime/tls/ca-cert.pem";
        trusted_client_ca = "/var/lib/keylime/tls/ca-cert.pem";
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

    # When a registrar CA cert is provided, enable TLS toward the registrar
    # and use the same CA for verifier mTLS, unless the user overrides them.
    services.keylime-agent.settings = lib.mkIf (cfg.registrar.caCertFile != null) {
      registrar_tls_enabled = lib.mkDefault true;
      registrar_tls_ca_cert = lib.mkDefault "/etc/keylime/registrar-ca.pem";
      trusted_client_ca = lib.mkDefault "/etc/keylime/registrar-ca.pem";
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

    systemd.mounts = [
      {
        description = "Keylime secure tmpfs";
        before = [ "keylime-agent.service" ];
        wantedBy = [ "multi-user.target" ];
        what = "tmpfs";
        where = "/var/lib/keylime/secure";
        type = "tmpfs";
        options = "mode=0700,size=1m,uid=keylime,gid=keylime";
      }
    ];

    systemd.services.keylime-agent = {
      description = "Keylime Agent";
      requires = [ "var-lib-keylime-secure.mount" ];
      after = [
        "network-online.target"
        "var-lib-keylime-secure.mount"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        RUST_LOG = cfg.logLevel;
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/keylime_agent";
        Restart = "on-failure";
        RestartSec = "5s";
        StateDirectory = "keylime";
        StateDirectoryMode = "0750";
      };
    };
  };
}
