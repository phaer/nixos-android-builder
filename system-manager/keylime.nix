# Keylime server (registrar + verifier) module for system-manager.
#
# This is the same as modules/keylime.nix but adapted for non-NixOS hosts.
# The main difference is that security.tpm2 comes from ./tpm2.nix (our
# system-manager port) instead of the NixOS module.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.keylime;
  tlsCfg = cfg.tls;
  keylimePkg = cfg.package;

  tlsDir = "/var/lib/keylime/tls";
  caCert = "${tlsDir}/ca-cert.pem";
  caKey = "${tlsDir}/ca-key.pem";
  serverCert = "${tlsDir}/server-cert.pem";
  serverKey = "${tlsDir}/server-key.pem";
  clientCert = "${tlsDir}/client-cert.pem";
  clientKey = "${tlsDir}/client-key.pem";

  # Shell script that generates a full mTLS PKI if the CA cert does not yet
  # exist.  Idempotent: re-running after certs are already present is a no-op.
  generateCertsScript = pkgs.writeShellScript "keylime-generate-certs" ''
    set -euo pipefail

    if [ -f "${caCert}" ]; then
      echo "keylime-tls: certificates already exist, skipping generation"
      exit 0
    fi

    echo "keylime-tls: generating mTLS PKI in ${tlsDir} …"
    mkdir -p "${tlsDir}"

    HOSTNAME="$(${pkgs.inetutils}/bin/hostname -f 2>/dev/null || ${pkgs.inetutils}/bin/hostname)"
    SANS="DNS:$HOSTNAME,DNS:localhost,IP:127.0.0.1"
    ${lib.concatMapStringsSep "\n" (s: ''SANS="$SANS,${s}"'') tlsCfg.subjectAlternativeNames}

    # --- CA ---
    ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "${caKey}" \
      -out "${caCert}" \
      -days ${toString tlsCfg.certLifetime} \
      -subj '/CN=Keylime CA' \
      -addext 'basicConstraints=critical,CA:TRUE' \
      -addext 'keyUsage=critical,keyCertSign,cRLSign'

    # --- server cert ---
    ${pkgs.openssl}/bin/openssl req -newkey rsa:2048 -nodes \
      -keyout "${serverKey}" \
      -out "${tlsDir}/server.csr" \
      -subj '/CN=keylime-server'

    ${pkgs.openssl}/bin/openssl x509 -req \
      -in "${tlsDir}/server.csr" \
      -CA "${caCert}" \
      -CAkey "${caKey}" \
      -CAcreateserial \
      -out "${serverCert}" \
      -days ${toString tlsCfg.certLifetime} -sha256 \
      -extfile <(printf "subjectAltName=$SANS")

    # --- client cert (verifier → registrar mTLS) ---
    ${pkgs.openssl}/bin/openssl req -newkey rsa:2048 -nodes \
      -keyout "${clientKey}" \
      -out "${tlsDir}/client.csr" \
      -subj '/CN=keylime-client'

    ${pkgs.openssl}/bin/openssl x509 -req \
      -in "${tlsDir}/client.csr" \
      -CA "${caCert}" \
      -CAkey "${caKey}" \
      -CAcreateserial \
      -out "${clientCert}" \
      -days ${toString tlsCfg.certLifetime} -sha256

    # --- clean up CSRs ---
    rm -f "${tlsDir}"/*.csr "${tlsDir}"/*.srl

    # --- permissions ---
    chown -R keylime:keylime "${tlsDir}"
    chmod 0750 "${tlsDir}"
    chmod 0640 "${tlsDir}"/*.pem

    echo "keylime-tls: PKI generation complete"
  '';

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

  registrarConf = toINI {
    registrar = registrarDefaults // cfg.registrar.settings;
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
      default = pkgs.callPackage ../packages/keylime { };
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

    tls = {
      autoGenerate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Automatically generate a self-signed CA and mTLS certificates
          in `/var/lib/keylime/tls/` on first activation.  Existing
          certificates are never overwritten.

          When enabled the registrar and verifier settings are
          automatically pointed at the generated files unless
          overridden explicitly.
        '';
      };

      certLifetime = lib.mkOption {
        type = lib.types.int;
        default = 365;
        description = "Validity period in days for generated certificates.";
      };

      subjectAlternativeNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "DNS:keylime.example.com"
          "IP:10.0.0.1"
        ];
        description = ''
          Additional Subject Alternative Names for the server certificate.
          The hostname, `localhost`, and `127.0.0.1` are always included.
          Each entry must use the `TYPE:value` format (e.g. `DNS:…` or `IP:…`).
        '';
      };
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
      "d ${tlsDir} 0750 keylime keylime -"
    ];

    # When autoGenerate is on, point registrar & verifier at the generated
    # files.  User-supplied settings (higher priority) override these.
    services.keylime.registrar.settings = lib.mkIf (tlsCfg.autoGenerate && cfg.registrar.enable) {
      tls_dir = lib.mkDefault tlsDir;
      server_key = lib.mkDefault serverKey;
      server_cert = lib.mkDefault serverCert;
      trusted_client_ca = lib.mkDefault [ caCert ];
    };

    services.keylime.verifier.settings = lib.mkIf (tlsCfg.autoGenerate && cfg.verifier.enable) {
      tls_dir = lib.mkDefault tlsDir;
      server_key = lib.mkDefault serverKey;
      server_cert = lib.mkDefault serverCert;
      trusted_client_ca = lib.mkDefault [ caCert ];
      client_key = lib.mkDefault clientKey;
      client_cert = lib.mkDefault clientCert;
      trusted_server_ca = lib.mkDefault [ caCert ];
    };

    environment.etc =
      keylimeEtc "keylime/ca.conf" caConf
      // keylimeEtc "keylime/logging.conf" loggingConf
      // lib.optionalAttrs cfg.registrar.enable (keylimeEtc "keylime/registrar.conf" registrarConf)
      // lib.optionalAttrs cfg.verifier.enable (keylimeEtc "keylime/verifier.conf" verifierConf);

    systemd.services =
      lib.optionalAttrs tlsCfg.autoGenerate {
        keylime-tls = {
          description = "Generate Keylime mTLS certificates";
          wantedBy = [ "system-manager.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = generateCertsScript;
          };
        };
      }
      // lib.optionalAttrs cfg.registrar.enable {
        keylime-registrar = {
          description = "Keylime Registrar";
          after = [
            "network-online.target"
          ]
          ++ lib.optional tlsCfg.autoGenerate "keylime-tls.service";
          wants = [ "network-online.target" ];
          requires = lib.optional tlsCfg.autoGenerate "keylime-tls.service";
          wantedBy = [ "system-manager.target" ];
          serviceConfig = commonServiceConfig // {
            ExecStart = "${keylimePkg}/bin/keylime_registrar";
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
          ++ lib.optional tlsCfg.autoGenerate "keylime-tls.service";
          wants = [ "network-online.target" ];
          requires = lib.optional tlsCfg.autoGenerate "keylime-tls.service";
          wantedBy = [ "system-manager.target" ];
          serviceConfig = commonServiceConfig // {
            ExecStart = "${keylimePkg}/bin/keylime_verifier";
          };
        };
      };
  };
}
