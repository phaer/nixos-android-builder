{
  lib,
  config,
  pkgs,
  ...
}:
let
  disk-installer = pkgs.callPackage ./. { };
  cfg = config.diskInstaller;
in
  {
    

  options.diskInstaller = {
      debug = (lib.mkEnableOption "verbose logging and a debug shell") // { default  = true; };
    };

    config = {
      system.stateVersion = "25.11";

      # noop settings to appease nixos modules system
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "none";
        fsType = "tmpfs";
      };

      virtualisation.vmVariant.virtualisation = {
        cores = 8;
        memorySize = 1024 * 8;
        graphics = false;
        fileSystems = lib.mkForce {};
        diskImage = lib.mkForce null;
      };

      boot.kernelParams = lib.optionals cfg.debug [
        "rd.systemd.debug_shell=ttyS0"
      ];

      boot.initrd.systemd = {
        emergencyAccess = cfg.debug;

        enable = true;
        contents."/etc/terminfo".source = "${pkgs.ncurses}/share/terminfo";

        initrdBin = [
          pkgs.parted
          disk-installer.run
        ];
        extraBin = {
          lsblk = "${pkgs.util-linux}/bin/lsblk";
          tee = "${pkgs.coreutils}/bin/tee";
          jq = "${pkgs.jq}/bin/jq";
          ddrescue = "${pkgs.ddrescue}/bin/ddrescue";
          dialog = "${pkgs.dialog}/bin/dialog";
          systemd-cat = "${pkgs.systemdMinimal}/bin/systemd-cat";
          chvt = "${pkgs.kbd}/bin/chvt";
        };


        targets.initrd-switch-root.enable = true;
        services = {
          initrd-switch-root.enable = true;
          initrd-cleanup.enable = true;
          initrd-parse-etc.enable = false;
          initrd-nixos-activation.enable = false;
          initrd-find-nixos-closure.enable = false;

          disk-installer = {
            description = "Early user prompt during initrd";

            after = [
              "initrd-root-device.target"
              "boot.mount"
            ];
            wantedBy = [ "initrd.target" ];

            unitConfig = {
              DefaultDependencies = false;
              ConditionPathExists = "/boot/install_target";
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
              install_source = "/dev/disk/by-partlabel/payload";
            };
            script = lib.getExe disk-installer.run;
          };
        };
      };
    };
  }
