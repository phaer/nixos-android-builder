# Auto-enrollment of new Keylime agents.
#
# Runs an HTTPS endpoint that accepts PCR policy reports from agents,
# and polls the registrar for newly registered agents.  When an agent
# is both registered AND has submitted its full PCR report, it is
# automatically enrolled with the verifier using the complete TPM
# policy (firmware PCRs 0-3, 7 + PCR 11).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.keylime;
  autoEnroll = cfg.autoEnroll;
  shared = import ../modules/lib/keylime-shared.nix { inherit lib pkgs; };

  tlsDir = "/var/lib/keylime/tls";

  autoEnrollScript = pkgs.writers.writePython3 "keylime-auto-enroll" {
  } (builtins.readFile ./keylime-auto-enroll.py);
in
{
  options.services.keylime.autoEnroll = {
    enable = lib.mkEnableOption "automatic enrollment of new Keylime agents with full PCR policy";

    pollInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Seconds between polling the registrar for new agents.";
    };

    enrollPort = lib.mkOption {
      type = lib.types.int;
      default = 8893;
      description = "HTTPS port for the PCR report endpoint that agents POST to.";
    };
  };

  config = lib.mkIf (cfg.enable && autoEnroll.enable) {
    systemd.services.keylime-auto-enroll = {
      description = "Auto-enroll new Keylime agents with full PCR policy";
      after = [
        "keylime-registrar.service"
        "keylime-verifier.service"
      ]
      ++ lib.optional cfg.tls.autoGenerate "keylime-tls.service";
      wants = [
        "keylime-registrar.service"
        "keylime-verifier.service"
      ];
      wantedBy = [ "system-manager.target" ];

      path = [
        cfg.package
      ];

      environment = {
        KEYLIME_TLS_DIR = tlsDir;
        KEYLIME_POLL_INTERVAL = toString autoEnroll.pollInterval;
        KEYLIME_ENROLL_PORT = toString autoEnroll.enrollPort;
      };

      serviceConfig = shared.commonServiceConfig // {
        ExecStart = autoEnrollScript;
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
