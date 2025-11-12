{
  lib,
  config,
  pkgs,
  modulesPath,
  ...
}:
let
  disk-installer = pkgs.callPackage ./. { };
  cfg = config.diskInstaller;
in
  {
    

  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  options.diskInstaller = {
      debug = (lib.mkEnableOption "verbose logging and a debug shell") // { default  = true; };
    };

    config = {
      system.stateVersion = "25.11";
      system.name = "disk-installer";

      # noop settings to appease nixos modules system
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "none";
        fsType = "tmpfs";
      };

      virtualisation.vmVariant.virtualisation = {
        diskImage = "${config.system.build.image}/${config.image.filePath}";
        cores = 8;
        memorySize = 1024 * 8;
        directBoot.enable = false;
        installBootLoader = false;
        useBootLoader = true;
        useEFIBoot = true;
        mountHostNixStore = false;
        efi.keepVariables = false;

        # NixOS overrides filesystems for VMs by default
        fileSystems = lib.mkForce { };
        useDefaultFilesystems = false;

        qemu.drives = lib.mkForce [
          {
            deviceExtraOpts = {
              bootindex = "1";
              serial = "root";
            };
            driveExtraOpts = {
              cache = "writeback";
              werror = "report";
              format = "raw";
              readonly = "on";
            };
            file = "\"$NIX_DISK_IMAGE\"";
            name = "root";
          }
        ];
      };

      boot.kernelParams = lib.optionals cfg.debug [
        "rd.systemd.debug_shell=tty1"
      ];

      image.repart = {
        mkfsOptions.erofs = [
          "-zlz4"
          "-Efragments,ztailpacking"
        ];
        sectorSize = 512;
        name = config.system.name;

        partitions = {
          "00-esp" = let
            efiArch = config.nixpkgs.hostPlatform.efiArch;
            efiUki = "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI";
          in {
            contents = {
              "${efiUki}".source = "${config.system.build.uki}/nixos.efi";
            };
            repartConfig = {
              Type = "esp";
              Label = "disk-installer";
              Format = "vfat";
              SizeMinBytes = "128M";
            };
          };
        };
      };


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
