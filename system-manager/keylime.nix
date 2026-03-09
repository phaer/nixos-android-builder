# Keylime server (registrar + verifier) module for system-manager.
#
# Shares options, defaults, and config generation with modules/keylime.nix
# via keylime-shared.nix. Adds TLS auto-generation and uses
# system-manager.target instead of multi-user.target.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.keylime;
  tlsCfg = cfg.tls;
  shared = import ../modules/lib/keylime-shared.nix { inherit lib pkgs; };
  keylimePkg = cfg.package;

  tlsDir = "/var/lib/keylime/tls";
  caCert = "${tlsDir}/ca-cert.pem";
  caKey = "${tlsDir}/ca-key.pem";
  serverCert = "${tlsDir}/server-cert.pem";
  serverKey = "${tlsDir}/server-key.pem";
  clientCert = "${tlsDir}/client-cert.pem";
  clientKey = "${tlsDir}/client-key.pem";

  generateCertsScript = pkgs.writers.writePython3 "keylime-generate-certs" {
    libraries = [ ];
  } (builtins.readFile ./keylime-generate-certs.py);
in
{
  options.services.keylime = shared.mkOptions (pkgs.callPackage ../packages/keylime { }) // {
    tls = {
      autoGenerate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Automatically generate a self-signed CA and mTLS certificates
          in `/var/lib/keylime/tls/` on first activation.  Existing
          certificates are never overwritten.

          When enabled the registrar, verifier, and tenant settings are
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
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ keylimePkg ];

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

    # When autoGenerate is on, point registrar, verifier, and tenant at
    # the generated files. User-supplied settings override these.
    services.keylime.registrar.settings = lib.mkIf (tlsCfg.autoGenerate && cfg.registrar.enable) {
      tls_dir = lib.mkDefault tlsDir;
      server_key = lib.mkDefault serverKey;
      server_cert = lib.mkDefault serverCert;
      trusted_client_ca = lib.mkDefault [ caCert ];
    };

    services.keylime.tenant.settings = lib.mkIf tlsCfg.autoGenerate {
      tls_dir = lib.mkDefault tlsDir;
      client_key = lib.mkDefault clientKey;
      client_cert = lib.mkDefault clientCert;
      trusted_server_ca = lib.mkDefault [ caCert ];
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

    environment.etc = shared.mkEtcFiles cfg;

    systemd.services =
      lib.optionalAttrs tlsCfg.autoGenerate {
        keylime-tls = {
          description = "Generate Keylime TLS certificates";
          wantedBy = [ "system-manager.target" ];
          path = [
            pkgs.openssl
            pkgs.iproute2
            pkgs.coreutils
          ];
          environment = {
            KEYLIME_TLS_DIR = tlsDir;
            KEYLIME_CERT_DAYS = toString tlsCfg.certLifetime;
            KEYLIME_EXTRA_SANS = builtins.toJSON tlsCfg.subjectAlternativeNames;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = generateCertsScript;
          };
        };
      }
      // shared.mkServices {
        inherit cfg;
        wantedBy = [ "system-manager.target" ];
        extraAfter = lib.optionalAttrs tlsCfg.autoGenerate {
          registrar = [ "keylime-tls.service" ];
          verifier = [ "keylime-tls.service" ];
        };
      };
  };
}
