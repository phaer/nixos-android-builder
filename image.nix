{lib, pkgs, config, modulesPath, ...}: {
  imports = [
    "${modulesPath}/image/repart.nix"
    "${modulesPath}/profiles/minimal.nix"
  ];

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
        device = "/dev/disk/by-partlabel/${config.systemd.repart.partitions."var".Label}";
        fsType = config.systemd.repart.partitions."var".Format;
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
        options = [ "ro" ];
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

    boot.initrd.systemd.extraBin."mkfs.ext4" = lib.getExe' pkgs.e2fsprogs "mkfs.ext4";
    boot.initrd.systemd.repart = {
      enable = true;
      # TODO we need better way to find the right disk, which might e.g. be /dev/sdb, sdc or nvme0n1p0.
      # maybe a custom udev rule?
      device = lib.mkDefault "/dev/vdb";
      empty = lib.mkDefault "require";
    };
    systemd.repart.partitions."var" = {
      Type = "var";
      UUID = "4d21b016-b534-45c2-a9fb-5c16e091fd2d"; # Well known
      Format = "ext4";
      Label = "var";
      Minimize = "off";
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
                    "${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
                  "/EFI/systemd/systemd-boot${efiArch}.efi".source =
                    "${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
                  "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
                    "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
                };
            repartConfig = {
              Type = "esp";
              Label = "boot";
              UUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"; # Well known
              Format = "vfat";
              SizeMinBytes = if config.nixpkgs.hostPlatform.isx86_64 then "64M" else "96M";
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
        };
      };
    };
  };
}
