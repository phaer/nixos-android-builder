{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = {
    # The NixOS default activation script to create /usr/bin/env assumes a
    # writable /usr/ file system. That's not the case for us, so we disable
    # it and add a bind mount from /usr/bin to /bin while building the image
    # below.
    system = {
      image = {
        id = config.system.name;
        version = config.system.nixos.version;
      };
      # Disable activation script that tries to create /usr/bin/env at runtime,
      # as that will fail with a verity-backed, read-only /usr
      activationScripts.usrbinenv = lib.mkForce "";
    };

    # Updating the random seed on /boot can not work with a read-only /boot.
    systemd.services.systemd-boot-random-seed.enable = lib.mkForce false;

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
          device = "/dev/mapper/var_lib_crypt";
          fsType = parts."30-var-lib".repartConfig.Format;
          neededForBoot = true;
        };
        "/boot" = {
          device = "/dev/disk/by-partlabel/${parts."00-esp".repartConfig.Label}";
          fsType = parts."00-esp".repartConfig.Format;
          options = [ "ro" ];
        };
        "/usr/bin" = {
          # Bind-mount /usr/bin to /bin. Mostly to get /usr/bin/env in place.
          # We bind the whole directory because it has no extra cost and
          # we don't know what tools inside the fhsenv might expect /usr/bin paths.
          device = "/bin";
          options = [
            "bind"
            "x-systemd.requires=bin.mount"
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
                mkdir -p $out
              '';
            };
            repartConfig = {
              Label = "store";
              Minimize = "best";
            };
          };
          "30-var-lib".repartConfig = {
            Type = "var";
            Format = "ext4";
            Label = "var-lib";
            # We want to start out with a very small partition in the image, and add
            # the real minimum size to to systemd.repart.partitions below instead,
            # in order to resize it during boot.
            SizeMinBytes = "10M";
          };
        };
      };
    };

    ## Run-time configuration of systemd-repart on first boot.
    # Reuse settings of the repart-generated image file on first boot
    systemd.repart.partitions."30-var-lib" =
      config.image.repart.partitions."30-var-lib".repartConfig
      // {
        Encrypt = "key-file";
        SizeMinBytes = "250G";
        # Tell systemd-repart to re-format and re-encrypt this partition on each boot
        # if run with --factory-reset, which we do by default.
        FactoryReset = true;
      };

    boot.initrd.luks.devices."var_lib_crypt" = {
      keyFile = "/etc/disk.key";
      device = "/dev/disk/by-partlabel/var-lib";
    };

    boot.initrd.systemd =
      let
        waitForDisk = pkgs.writeScript "wait-for-disk" ''
          #!/bin/sh
          set -e
          partprobe
          udevadm settle -t 5
        '';
        generateDiskKey = pkgs.writeScript "generate-disk-key" ''
          #!/bin/sh
          set -e
          umask 0077
          head -c 64 /dev/urandom > /etc/disk.key
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
          generateDiskKey
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
          extraArgs = [
            "--key-file=/etc/disk.key"
            # --factory-reset instructs systemd-repart to reset all partitions marked with FactoryReset=true,
            # only /var/lib in our case. The read-only partitions stay in place.
            "--factory-reset=true"
          ];
        };

        services = {
          systemd-repart = {
            before = [
              "systemd-cryptsetup@var_lib_crypt.service"
            ];
            serviceConfig.ExecStartPost = waitForDisk;
          };

          generate-disk-key = {
            description = "Generate a secure, ephemeral key to encrypt the persistent disk with";
            wantedBy = [ "initrd.target" ];
            before = [ "systemd-repart.service" ];
            requiredBy = [ "systemd-repart.service" ];
            unitConfig = {
              DefaultDependencies = false;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = generateDiskKey;
            };
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
                config.image.repart.partitions."30-var-lib".repartConfig.Label
              } /run/systemd/volatile-root'';
            };
          };
        };
      };
  };
}
