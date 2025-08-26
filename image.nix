{
  lib,
  config,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/image/repart.nix"
    "${modulesPath}/profiles/minimal.nix"
    "${modulesPath}/profiles/perlless.nix"
  ];

  options.boot.initrd.systemd.repart = {
    keyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "key file to use for LUKS encryption";
      default = null;
    };

    factoryReset = lib.mkOption {
      type = lib.types.bool;
      description = "whether to use systemd factory reset facilities";
      default = false;
    };
  };

  config = {
    fileSystems =
      let
        parts = config.image.repart.partitions;
      in
      {
        "/" = {
          device = "none";
          fsType = "tmpfs";
          options = [
            "size=20%"
            "mode=0755"
          ];
        };
        "/var/lib" = {
          device = "/dev/disk/by-partlabel/${parts."30-var-lib".repartConfig.Label}";
          fsType = parts."30-var-lib".repartConfig.Format;
          neededForBoot = true;
        };
        "/boot" = {
          device = "/dev/disk/by-partlabel/${parts."00-esp".repartConfig.Label}";
          fsType = parts."00-esp".repartConfig.Format;
          options = [ "ro" ];
        };
        "/nix/store" = {
          overlay = {
            lowerdir = [ "/nix/.ro-store" ];
            upperdir = "/nix/.rw-store/upper";
            workdir = "/nix/.rw-store/work";
          };
        };
        "/nix/.ro-store" = {
          device = "/usr/nix/store";
          options = [ "bind" ];
          neededForBoot = true;
        };
        "/nix/.rw-store" = {
          device = "none";
          fsType = "tmpfs";
          options = [
            "size=20%"
            "mode=0755"
          ];
        };
      };

    system.image = {
      id = config.system.name;
      version = config.system.nixos.version;
    };

    # Updating the random seed on /boot can not work with a read-only /boot.
    systemd.services.systemd-boot-random-seed.enable = lib.mkForce false;

    # Link /var/run to /run to appease systemd
    boot.initrd.systemd.tmpfiles.settings = {
      "1-var-run" = {
        "/var/run" = {
          L = {
            argument = "/run";
          };
        };
      };
    };

    image = {
      repart = {
        # OVMF does not work with the default repart sector size of 4096
        sectorSize = 512;

        name = config.system.name;
        #compression.enable = true;
        #compression.algorithm = "zstd";

        verityStore =
          let
            efiArch = config.nixpkgs.hostPlatform.efiArch;
            efiUki = "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI";
          in
          {
            enable = true;
            ukiPath = efiUki;
            partitionIds = {
              esp = "00-esp";
              store-verity = "10-store-verity";
              store = "20-store";
            };
          };

        partitions = {
          "00-esp".repartConfig = {
            Type = "esp";
            Label = "boot";
            UUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"; # Well known
            Format = "vfat";
            SizeMinBytes = "128M";
          };
          "10-store-verity".repartConfig = {
            Label = "store-verity";
            Minimize = "best";
          };
          "20-store" = {
            storePaths = [ config.system.build.toplevel ];
            repartConfig = {
              Label = "store";
              Minimize = "best";
            };
          };
          "30-var-lib".repartConfig = {
            Type = "var";
            UUID = "4d21b016-b534-45c2-a9fb-5c16e091fd2d"; # Well known
            Format = "ext4";
            Label = "var-lib";
          };
        };
      };
    };

    boot.initrd.systemd.repart.extraArgs =
      let
        initrdCfg = config.boot.initrd.systemd.repart;
      in
      (lib.optionals (initrdCfg.keyFile != null) [ "--key-file=${initrdCfg.keyFile}" ])
      ++ (lib.optionals (initrdCfg.factoryReset) [ "--factory-reset=true" ]);
  };
}
