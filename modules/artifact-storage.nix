# Store outputs on an unecrypted, persistent disk partition
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.nixosAndroidBuilder.artifactStorage;
in
{
  options.nixosAndroidBuilder.artifactStorage = {
    enable = lib.mkEnableOption "";
    diskLabel = lib.mkOption {
      default = "artifacts";
      type = lib.types.str;
    };
  };

  config = lib.mkIf cfg.enable {

    fileSystems."/var/lib/artifacts" = {
      device = "/dev/disk/by-label/${cfg.diskLabel}";
      fsType = "ext4";
    };

    boot.initrd.systemd = {
      contents."/etc/terminfo".source = "${pkgs.ncurses}/share/terminfo";
      units."dev-disk-by\\x2dlabeli-artifacts.device.d/timeout.conf" = {
        text = ''
          [Unit]
        JobTimeoutSec=Infinity
        '';
      };


      extraBin = {
        lsblk = "${pkgs.util-linux}/bin/lsblk";
        blkid = "${pkgs.util-linux}/bin/blkid";
        tee = "${pkgs.coreutils}/bin/tee";
        jq = "${pkgs.jq}/bin/jq";
        dialog = "${pkgs.dialog}/bin/dialog";
        systemd-cat = "${pkgs.systemdMinimal}/bin/systemd-cat";
        chvt = "${pkgs.kbd}/bin/chvt";
      };

      services = {
        prepare-artifact-storage = {
          description = "Prepare unencrypted, persistent output storage";

          after = [
            "systemd-udev-settle.service"
          ];
          before = [
            "initrd-switch-root.service"
            ];
          wantedBy = [
            "initrd-switch-root.target"
            "rescue.target"
          ];
          requiredBy = [
            "initrd-switch-root.target"
            "rescue.target"
          ];

          unitConfig = {
            DefaultDependencies = false;
          };

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardInput = "tty-force";
            StandardOutput = "tty";
            StandardError = "tty";
            TTYPath = "/dev/tty2";
            TTYReset = true;
            Restart = "no";
          };
          onFailure = [ "emergency.target" ];

          environment = {
            DISK_LABEL = cfg.diskLabel;
          };

          script = builtins.readFile ./artifact-storage.sh;
        };
      };
    };
  };
}
