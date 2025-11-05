{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = {
    system = {
      image = {
        id = config.system.name;
        version = config.system.nixos.version;
      };
    };

    # Updating the random seed on /boot can not work with a read-only /boot.
    systemd.services.systemd-boot-random-seed.enable = lib.mkForce false;

    # add veritysetup to PATH, it's not there by default if we just use dm-verity,
    # but no, optional, encrypted partition
    environment.systemPackages = [
      pkgs.cryptsetup
    ];

    # Disable activation script that tries to create /usr/bin/env at runtime,
    # as that will fail with a verity-backed, read-only /usr
    # The NixOS default activation script to create /usr/bin/env assumes a
    # writable /usr/ file system. That's not the case for us, so we disable
    # it and add a bind mount from /usr/bin to /bin.
    system.activationScripts.usrbinenv = lib.mkForce "";

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
        "/boot" = {
          device = "/dev/disk/by-partlabel/${parts."00-esp".repartConfig.Label}";
          fsType = parts."00-esp".repartConfig.Format;
          options = [ "ro" ];
        };
        "/usr/bin/env" = {
          # Bind-mount /usr/bin/env in place
          device = pkgs.lib.getExe' pkgs.coreutils "env";
          options = [
            "bind"
            "ro"
          ];
          neededForBoot = false;
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

    ## Build-time configuration of systemd-repart during image build
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
            Format = "vfat";
            SizeMinBytes = "128M";
          };
          "10-store-verity".repartConfig = {
            Label = "store-verity";
            Minimize = "best";
          };
          "20-store" = {
            storePaths = [ config.system.build.toplevel ];
            contents = {
              # Create an empty dir at /usr/bin, in order to bind-mount /bin at run-time
              "/bin".source = pkgs.runCommand "usr-bin-symlink" { } ''
                mkdir -p $out; touch $out/env
              '';
            };
            repartConfig = {
              Label = "store";
              Minimize = "best";
            };
          };
        };
      };
    };

    boot.initrd.systemd =
      let
        waitForDisk = pkgs.writeScript "wait-for-disk" ''
          #!/bin/sh
          set -e
          partprobe
          udevadm settle -t 5
        '';
      in
      {
        # Add mkfs, fsck, etc for ext4 to initrd
        initrdBin = [ pkgs.e2fsprogs ];
        # Add just the partprobe binary from parted.
        extraBin = {
          partprobe = "${pkgs.parted}/bin/partprobe";
        };
        # We need to list our scripts here, otherwise store paths won't be in initrd
        storePaths = [
          waitForDisk
        ];

        # Link /var/run to /run to appease systemd
        tmpfiles.settings = {
          "1-var-run" = {
            "/var/run" = {
              L = {
                argument = "/run";
              };
            };
          };
        };

        # Run systemd-repart in initrd at boot
        repart = {
          enable = true;
          extraArgs =
            (lib.optional config.nixosAndroidBuilder.ephemeralVarLib "--key-file=/etc/disk.key")
            ++ [
              # --factory-reset instructs systemd-repart to reset all partitions marked with FactoryReset=true,
              # only /var/lib in our case. The read-only partitions stay in place.
              "--factory-reset=true"
            ];
        };

        services = {
          systemd-repart = {
            environment."SYSTEMD_REPART_MKFS_OPTIONS_EXT4" = "-O ^dir_index";
            serviceConfig.ExecStartPost = waitForDisk;
          };

          # Link the read-only nix store to /run/systemd/volatile-root before
          # systemd-repart runs. systemd-repart normally looks for the block device
          # backing "/", or this path. So this enables systemd-repart to find the
          # right device at boot.
          link-volatile-root = {
            description = "Create volatile-root to tell systemd-repart which disk to use";
            wantedBy = [ "initrd.target" ];
            before = [ "systemd-repart.service" ];
            requiredBy = [ "systemd-repart.service" ];
            unitConfig = {
              DefaultDependencies = false;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = ''/bin/ln -sf /dev/disk/by-partlabel/${
                config.image.repart.partitions."20-store".repartConfig.Label
              } /run/systemd/volatile-root'';
            };
          };
        };
      };
  };
}
