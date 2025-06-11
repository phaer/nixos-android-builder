{lib, config, pkgs, modulesPath, ...}: {
  imports = [
    "${modulesPath}/image/repart.nix"
    "${modulesPath}/profiles/minimal.nix"
  ];

  config = let
    closureInfo = pkgs.closureInfo {
      rootPaths = [ config.system.build.toplevel ];
    };

    # Build the nix state at /nix/var/nix for the image
    #
    # This does two things:
    # (1) Setup the initial profile
    # (2) Create an initial Nix DB so that the nix tools work
    nixState = pkgs.runCommand "nix-state" { nativeBuildInputs = [ pkgs.buildPackages.nix ]; } ''
      mkdir -p $out/profiles
    ln -s ${config.system.build.toplevel} $out/profiles/system-1-link
    ln -s /nix/var/nix/profiles/system-1-link $out/profiles/system

    export NIX_STATE_DIR=$out
    nix-store --load-db < ${closureInfo}/registration
    '';

  in {
    #fileSystems = {
    #  "/" = lib.mkForce {
    #    device = "none";
    #    fsType = "tmpfs";
    #    options = [ "defaults" "size=2G" "mode=755" ];
    #  };
    #};
    fileSystems = {
      "/" = {
        device = "/dev/disk/by-partlabel/nixos";
        fsType = "ext4";
      };
    };

    # By not providing an entry in fileSystems for the ESP, systemd will
    # automount it to `/efi`.
    boot.loader.efi.efiSysMountPoint = "/efi";

    system.image = {
      id = config.system.name;
      version = config.system.nixos.version;
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
              Format = "vfat";
              SizeMinBytes = if config.nixpkgs.hostPlatform.isx86_64 then "64M" else "96M";
            };
          };
          "root" = {
            storePaths = [ config.system.build.toplevel ];
            contents = {
              "/nix/var/nix".source = nixState;
            };
            repartConfig = {
              Type = "root";
              Format = config.fileSystems."/".fsType;
              Label = "nixos";
              Minimize = "guess";
            };
          };
        };
      };
    };
  };
}
