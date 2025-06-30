{lib, pkgs, config, modulesPath, ...}: let
  initrdCfg = config.boot.initrd.systemd.repart;
in {
  imports = [
    "${modulesPath}/image/repart.nix"
    "${modulesPath}/profiles/minimal.nix"
  ];

  # TODO upstream these options and the ExecStart changes for systemd-repart below
  options.boot.initrd.systemd.repart = {
    keyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "key file to use for LUKS encryption";
      default = null;
    };

    factoryReset = lib.mkOption {
      type = lib.types.bool;
      description = "";
      default = false;
    };
  };



  config = {
    fileSystems = let
      parts = config.image.repart.partitions;
    in {
      "/" = {
        device = "none";
        fsType = "tmpfs";
        options = [ "size=20%" "mode=0755" ];
      };
      "/var/lib" = {
        device = "/dev/disk/by-partlabel/${parts."var-lib".repartConfig.Label}";
        fsType = parts."var-lib".repartConfig.Format;
        neededForBoot = true;
      };
      "/boot" = {
        device = "/dev/disk/by-partlabel/${parts."esp".repartConfig.Label}";
        fsType = parts."esp".repartConfig.Format;
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
        device = "/dev/disk/by-partlabel/${parts."store".repartConfig.Label}";
        fsType = parts."store".repartConfig.Format;
        options = [ "ro" "x-systemd.after=systemd-repart.service" ];
        neededForBoot = true;
      };
      "/nix/.rw-store" = {
        device = "none";
        fsType = "tmpfs";
        options = [ "size=20%" "mode=0755" ];
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

        partitions = {
          "esp" = {
            # Populate the ESP statically so that we can boot this image.
            contents =
              let
                efiArch = config.nixpkgs.hostPlatform.efiArch;
              in
                {
                  "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
                    "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
                  "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
                    "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
                };
            repartConfig = {
              Type = "esp";
              Label = "boot";
              UUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"; # Well known
              Format = "vfat";
              SizeMinBytes = "128M";
            };
          };
          "store" = {
            storePaths = [ config.system.build.toplevel ];
            stripNixStorePrefix = true;
            repartConfig = {
              Type = "linux-generic";
              Label = "store";
              Format = "erofs";
              Minimize = "best";
            };
          };
          "var-lib".repartConfig = {
            Type = "var";
            UUID = "4d21b016-b534-45c2-a9fb-5c16e091fd2d"; # Well known
            Format = "ext4";
            Label = "var-lib";
          };
        };
      };
    };

    # The upstream service definition in nixpkgs currently does not allow us to pass
    # neither --key-file=, nor --factory-reset, so we patch them in.
    # TODO this can probably be upstreamed with the options for factoryReset & keyFile
    boot.initrd.systemd.services.systemd-repart.serviceConfig.ExecStart = [
      " " # required to unset the previous value.
      # When running in the initrd, systemd-repart by default searches
      # for definition files in /sysroot or /sysusr. We tell it to look
      # in the initrd itself.
      ''
      ${config.boot.initrd.systemd.package}/bin/systemd-repart \
        --definitions=/etc/repart.d \
        --dry-run=no \
        --empty=${initrdCfg.empty} \
        --discard=${lib.boolToString initrdCfg.discard} \
        --factory-reset=${lib.boolToString initrdCfg.factoryReset} \
        ${lib.optionalString (initrdCfg.keyFile != null) "--key-file=${initrdCfg.keyFile}"} \
        ${lib.optionalString (initrdCfg.device != null) initrdCfg.device}
      ''
    ];
  };
}
