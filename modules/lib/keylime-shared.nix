# Shared definitions for the keylime server NixOS module (modules/keylime.nix)
# and the system-manager port (system-manager/keylime.nix). Contains INI
# helpers, config defaults, option declarations, and config-file generators.
{ lib, pkgs, keylime ? pkgs.callPackage ../../packages/keylime { } }:

let
  measuredBootPolicy = pkgs.callPackage ../../packages/keylime-measured-boot-policy {
    inherit keylime;
  };

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
in
rec {
  inherit toINI;

  keylimeEtc = name: text: {
    ${name} = {
      inherit text;
      user = "keylime";
      group = "keylime";
      mode = "0440";
    };
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

  registrarDefaults = {
    version = "2.5";
    ip = "0.0.0.0";
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

  tenantDefaults = {
    version = "2.5";
    registrar_ip = "127.0.0.1";
    registrar_port = 8891;
    verifier_ip = "127.0.0.1";
    verifier_port = 8881;
    tls_dir = "default";
    client_key = "default";
    client_cert = "default";
    trusted_server_ca = "default";
    max_retries = 5;
    retry_interval = 2;
    accept_tpm_hash_algs = ''["sha512", "sha384", "sha256"]'';
    accept_tpm_encryption_algs = ''["ecc", "rsa"]'';
    accept_tpm_signing_algs = ''["ecschnorr", "rsassa"]'';
    require_ek_cert = false;
  };

  verifierDefaults = {
    version = "2.5";
    uuid = "default";
    ip = "0.0.0.0";
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
    measured_boot_policy_name = "uki";
    measured_boot_imports = ''["measured_boot_policy"]'';
    measured_boot_evaluate = "always";
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
    mode = "push";
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

  mkCaConf = toINI {
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

  mkLoggingConf =
    cfg:
    let
      # Convert a Python logger qualname (e.g. "keylime.web") to a safe INI
      # section identifier (e.g. "keylime_web") for fileConfig's [logger_*] sections.
      qualNameToId = name: builtins.replaceStrings [ "." ] [ "_" ] name;

      overrideNames = builtins.attrNames cfg.logLevelOverrides;
      overrideIds = map qualNameToId overrideNames;

      loggerKeys = [
        "root"
        "keylime"
      ]
      ++ overrideIds;

      overrideSections = lib.listToAttrs (
        map (name: {
          name = "logger_${qualNameToId name}";
          value = {
            level = cfg.logLevelOverrides.${name};
            qualname = name;
            handlers = "";
          };
        }) overrideNames
      );
    in
    toINI (
      {
        logging.version = "2.5";
        loggers.keys = lib.concatStringsSep "," loggerKeys;
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
      }
      // overrideSections
    );

  mkRegistrarConf =
    cfg:
    toINI {
      registrar = registrarDefaults // cfg.registrar.settings;
    };

  mkTenantConf =
    cfg:
    toINI {
      tenant = tenantDefaults // cfg.tenant.settings;
    };

  mkVerifierConf =
    cfg:
    let
      userSettings = builtins.removeAttrs cfg.verifier.settings [ "revocations" ];
    in
    toINI {
      verifier = verifierDefaults // userSettings;
      revocations = revocationDefaults // (cfg.verifier.settings.revocations or { });
    };

  mkOptions = keylimePkg: {
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

    logLevelOverrides = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.enum [
          "DEBUG"
          "INFO"
          "WARNING"
          "ERROR"
          "CRITICAL"
        ]
      );
      default = {
        "keylime.web" = "WARNING";
        "keylime.authorization.manager" = "WARNING";
      };
      description = ''
        Per-logger log level overrides. Keys are Python logger qualnames
        (e.g. `keylime.web`), values are log levels.

        By default, the noisy `keylime.web` and
        `keylime.authorization.manager` loggers are set to WARNING to
        suppress routine per-request INFO messages. Set to `{ }` to
        restore the previous behaviour.
      '';
    };

    measuredBootPolicyPath = lib.mkOption {
      type = lib.types.path;
      default = measuredBootPolicy.policyPath;
      description = ''
        Directory containing the measured boot policy Python module.
        Added to the verifier's PYTHONPATH. The module must register
        a policy name matching `measured_boot_policy_name` in
        verifier.conf.
      '';
    };

    registrar = {
      enable = lib.mkEnableOption "Keylime registrar service";
      settings = lib.mkOption {
        type = settingsType;
        default = { };
        description = "Settings for registrar.conf [registrar] section.";
      };
    };

    verifier = {
      enable = lib.mkEnableOption "Keylime verifier service";
      settings = lib.mkOption {
        type = settingsType;
        default = { };
        description = ''
          Settings for verifier.conf. A nested `revocations` attrset maps to
          the [revocations] INI section.
        '';
      };
    };

    tenant = {
      settings = lib.mkOption {
        type = settingsType;
        default = { };
        description = "Settings for tenant.conf [tenant] section.";
      };
    };
  };

  mkEtcFiles =
    cfg:
    keylimeEtc "keylime/ca.conf" mkCaConf
    // keylimeEtc "keylime/logging.conf" (mkLoggingConf cfg)
    // keylimeEtc "keylime/tenant.conf" (mkTenantConf cfg)
    // lib.optionalAttrs cfg.registrar.enable (
      keylimeEtc "keylime/registrar.conf" (mkRegistrarConf cfg)
    )
    // lib.optionalAttrs cfg.verifier.enable (keylimeEtc "keylime/verifier.conf" (mkVerifierConf cfg));

  mkServices =
    {
      cfg,
      wantedBy,
      extraAfter ? { },
    }:
    lib.optionalAttrs cfg.registrar.enable {
      keylime-registrar = {
        description = "Keylime Registrar";
        after = [ "network-online.target" ] ++ (extraAfter.registrar or [ ]);
        wants = [ "network-online.target" ];
        requires = extraAfter.registrar or [ ];
        inherit wantedBy;
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
        ++ lib.optional cfg.registrar.enable "keylime-registrar.service"
        ++ (extraAfter.verifier or [ ]);
        wants = [ "network-online.target" ];
        requires = extraAfter.verifier or [ ];
        inherit wantedBy;
        environment.PYTHONPATH = "${cfg.measuredBootPolicyPath}";
        serviceConfig = commonServiceConfig // {
          ExecStart = "${cfg.package}/bin/keylime_verifier";
        };
      };
    };

  mkFirewallPorts =
    cfg:
    lib.optionals cfg.registrar.enable [
      (cfg.registrar.settings.port or registrarDefaults.port)
      (cfg.registrar.settings.tls_port or registrarDefaults.tls_port)
    ]
    ++ lib.optional cfg.verifier.enable (cfg.verifier.settings.port or verifierDefaults.port);
}
