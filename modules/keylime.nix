{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.keylime;

  keylimePkg = pkgs.callPackage ../packages/keylime { };

  # Keylime's config.getlist() uses ast.literal_eval and expects Python list
  # literals (e.g. '["value"]') for certain options.
  mkValueString =
    v:
    if builtins.isList v then
      "[${lib.concatMapStringsSep ", " (s: ''"${s}"'') v}]"
    else if builtins.isBool v then
      (if v then "True" else "False")
    else if builtins.isInt v then
      toString v
    else if builtins.isString v then
      v
    else
      throw "unsupported INI value type: ${builtins.typeOf v}";

  toINI = lib.generators.toINI {
    mkKeyValue = lib.generators.mkKeyValueDefault { inherit mkValueString; } " = ";
  };

  keylimeEtc = name: text: {
    ${name} = {
      inherit text;
      user = "keylime";
      group = "keylime";
      mode = "0440";
    };
  };

  caConf = toINI {
    ca = {
      version = "2.5";
      password = "default";
      cert_country = "US";
      cert_ca_name = "Keylime Certificate Authority";
      cert_state = "MA";
      cert_locality = "Lexington";
      cert_organization = "MITLL";
      cert_org_unit = "53";
      cert_ca_lifetime = 3650;
      cert_lifetime = 365;
      cert_bits = 2048;
      cert_crl_dist = "http://localhost:38080/crl";
    };
  };

  loggingConf = toINI {
    logging.version = "2.5";
    loggers.keys = "root,keylime";
    handlers.keys = "consoleHandler";
    formatters.keys = "formatter";
    formatter_formatter = {
      format = "%(asctime)s.%(msecs)03d - %(name)s - %(levelname)s - %(message)s";
      datefmt = "%Y-%m-%d %H:%M:%S";
    };
    logger_root = {
      level = cfg.logLevel;
      handlers = "consoleHandler";
    };
    handler_consoleHandler = {
      class = "StreamHandler";
      level = cfg.logLevel;
      formatter = "formatter";
      args = "(sys.stdout,)";
    };
    logger_keylime = {
      level = cfg.logLevel;
      qualname = "keylime";
      handlers = "";
    };
  };

  commonServiceConfig = {
    User = "keylime";
    Group = "keylime";
    Restart = "on-failure";
    RestartSec = "10s";
    TimeoutSec = "60s";
    StateDirectory = "keylime";
    StateDirectoryMode = "0750";
    ProtectSystem = "strict";
    ProtectHome = true;
    ReadWritePaths = [ "/var/lib/keylime" ];
    PrivateTmp = true;
    NoNewPrivileges = true;
  };

  # Defaults taken from keylime 7.14.1 keylime/config.py
  registrarDefaults = {
    version = "2.5";
    ip = "127.0.0.1";
    port = 8890;
    tls_port = 8891;
    tls_dir = "default";
    server_key = "default";
    server_key_password = "";
    server_cert = "default";
    cert_subject_alternative_names = "";
    trusted_client_ca = "default";
    authorization_provider = "simple";
    database_url = "sqlite";
    database_pool_sz_ovfl = "5,10";
    auto_migrate_db = true;
    durable_attestation_import = "";
    persistent_store_url = "";
    transparency_log_url = "";
    time_stamp_authority_url = "";
    time_stamp_authority_certs_path = "";
    persistent_store_format = "json";
    persistent_store_encoding = "";
    transparency_log_sign_algo = "sha256";
    signed_attributes = "ek_tpm,aik_tpm,ekcert";
    tpm_identity = "default";
    malformed_cert_action = "warn";
  };

  registrarConf = toINI {
    registrar = registrarDefaults // cfg.registrar.settings;
  };

  # Defaults taken from keylime 7.14.1 keylime/config.py
  verifierDefaults = {
    version = "2.5";
    uuid = "default";
    ip = "127.0.0.1";
    port = 8881;
    registrar_ip = "127.0.0.1";
    registrar_port = 8891;
    enable_agent_mtls = true;
    tls_dir = "generate";
    server_key = "default";
    server_key_password = "";
    server_cert = "default";
    cert_subject_alternative_names = "";
    trusted_client_ca = "default";
    client_key = "default";
    client_key_password = "";
    client_cert = "default";
    trusted_server_ca = "default";
    authorization_provider = "simple";
    database_url = "sqlite";
    database_pool_sz_ovfl = "5,10";
    auto_migrate_db = true;
    num_workers = 0;
    exponential_backoff = true;
    retry_interval = 2;
    max_retries = 5;
    request_timeout = "60.0";
    quote_interval = 2;
    max_upload_size = 104857600;
    measured_boot_policy_name = "accept-all";
    measured_boot_imports = "[]";
    measured_boot_evaluate = "once";
    severity_labels = ''["info", "notice", "warning", "error", "critical", "alert", "emergency"]'';
    severity_policy = ''[{"event_id": ".*", "severity_label" : "emergency"}]'';
    ignore_tomtou_errors = false;
    durable_attestation_import = "";
    persistent_store_url = "";
    transparency_log_url = "";
    time_stamp_authority_url = "";
    time_stamp_authority_certs_path = "";
    persistent_store_format = "json";
    persistent_store_encoding = "";
    transparency_log_sign_algo = "sha256";
    signed_attributes = "";
    require_allow_list_signatures = false;
    mode = "pull";
    challenge_lifetime = 1800;
    verification_timeout = 0;
    session_create_rate_limit_per_ip = 50;
    session_create_rate_limit_window_ip = 60;
    session_create_rate_limit_per_agent = 15;
    session_create_rate_limit_window_agent = 60;
    session_lifetime = 180;
    extend_token_on_attestation = true;
  };

  revocationDefaults = {
    enabled_revocation_notifications = "[agent]";
    zmq_ip = "127.0.0.1";
    zmq_port = 8992;
    webhook_url = "";
  };

  verifierConf =
    let
      userSettings = builtins.removeAttrs cfg.verifier.settings [ "revocations" ];
    in
    toINI {
      verifier = verifierDefaults // userSettings;
      revocations = revocationDefaults // (cfg.verifier.settings.revocations or { });
    };

  settingsType = lib.types.attrsOf (
    lib.types.oneOf [
      lib.types.str
      lib.types.int
      lib.types.bool
      (lib.types.listOf lib.types.str)
      (lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.str
          lib.types.int
          lib.types.bool
          (lib.types.listOf lib.types.str)
        ]
      ))
    ]
  );

in
{
  options.services.keylime = {
    enable = lib.mkEnableOption "Keylime TPM-based remote attestation server";

    package = lib.mkOption {
      type = lib.types.package;
      default = keylimePkg;
      description = "The keylime package to use.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "DEBUG"
        "INFO"
        "WARNING"
        "ERROR"
        "CRITICAL"
      ];
      default = "INFO";
      description = "Log level for keylime services.";
    };

    registrar = {
      enable = lib.mkEnableOption "Keylime registrar service";

      settings = lib.mkOption {
        type = settingsType;
        default = { };
        description = ''
          Freeform settings for `registrar.conf` under the `[registrar]` section.
          Keys should use snake_case INI names (e.g. `tls_dir`, `server_key`).
          Values are merged over built-in defaults.
        '';
        example = {
          ip = "0.0.0.0";
          tls_dir = "/var/lib/keylime/tls";
          server_key = "/var/lib/keylime/tls/server-key.pem";
          server_cert = "/var/lib/keylime/tls/server-cert.pem";
          trusted_client_ca = [ "/var/lib/keylime/tls/ca-cert.pem" ];
        };
      };
    };

    verifier = {
      enable = lib.mkEnableOption "Keylime verifier service";

      settings = lib.mkOption {
        type = settingsType;
        default = { };
        description = ''
          Freeform settings for `verifier.conf` under the `[verifier]` section.
          Keys should use snake_case INI names (e.g. `tls_dir`, `server_key`).
          A nested `revocations` attrset is placed in the `[revocations]` INI section.
          Values are merged over built-in defaults.
        '';
        example = {
          ip = "0.0.0.0";
          tls_dir = "/var/lib/keylime/tls";
          server_key = "/var/lib/keylime/tls/server-key.pem";
          trusted_client_ca = [ "/var/lib/keylime/tls/ca-cert.pem" ];
          revocations = {
            enabled_revocation_notifications = "[agent, webhook]";
            webhook_url = "https://example.com/hook";
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    security.tpm2 = {
      enable = true;
      tctiEnvironment.enable = true;
    };

    users.users.keylime = {
      isSystemUser = true;
      group = "keylime";
      home = "/var/lib/keylime";
    };

    users.groups.keylime = { };

    systemd.tmpfiles.rules = [
      "d /var/lib/keylime 0750 keylime keylime -"
    ];

    environment.etc =
      keylimeEtc "keylime/ca.conf" caConf
      // keylimeEtc "keylime/logging.conf" loggingConf
      // lib.optionalAttrs cfg.registrar.enable (keylimeEtc "keylime/registrar.conf" registrarConf)
      // lib.optionalAttrs cfg.verifier.enable (keylimeEtc "keylime/verifier.conf" verifierConf);

    systemd.services =
      lib.optionalAttrs cfg.registrar.enable {
        keylime-registrar = {
          description = "Keylime Registrar";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = commonServiceConfig // {
            ExecStart = "${cfg.package}/bin/keylime_registrar";
          };
        };
      }
      // lib.optionalAttrs cfg.verifier.enable {
        keylime-verifier = {
          description = "Keylime Verifier";
          after = [
            "network-online.target"
          ]
          ++ lib.optional cfg.registrar.enable "keylime-registrar.service";
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = commonServiceConfig // {
            ExecStart = "${cfg.package}/bin/keylime_verifier";
          };
        };
      };
  };
}
