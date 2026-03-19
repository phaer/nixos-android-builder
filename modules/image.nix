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
    };

    # Updating the random seed on /boot can not work with a read-only /boot.
    systemd.services.systemd-boot-random-seed.enable = lib.mkForce false;

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
        "/var/lib/credentials" = {
          device = "/dev/mapper/var_lib_credentials_crypt";
          fsType = "ext4";
          neededForBoot = true;
        };
        "/var/lib/keylime" = {
          device = "/dev/mapper/var_lib_keylime_crypt";
          fsType = "ext4";
          neededForBoot = true;
        };
        "/var/lib/build" = {
          device = "/dev/mapper/var_lib_crypt";
          fsType = config.systemd.repart.partitions."40-var-lib-build".Format;
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
        "/nix/store" =
          if config.nixosAndroidBuilder.debug then
            {
              overlay = {
                lowerdir = [ "/nix/.ro-store" ];
                upperdir = "/nix/.rw-store/upper";
                workdir = "/nix/.rw-store/work";
              };
            }
          else
            {
              device = "/usr/nix/store";
              options = [ "bind" ];
              neededForBoot = true;
            };
        "/nix/.ro-store" = lib.mkIf config.nixosAndroidBuilder.debug {
          device = "/usr/nix/store";
          options = [ "bind" ];
          neededForBoot = true;
        };
        "/nix/.rw-store" = lib.mkIf config.nixosAndroidBuilder.debug {
          device = "none";
          fsType = "tmpfs";
          options = [
            "size=20%"
            "mode=0755"
          ];
        };
      };

    systemd.tmpfiles.rules = [
      "z /var/lib/build 0700 user user - -"
    ];

    # The fstab generator does not reliably activate mount units for
    # /boot and FHS bind mounts after  Require them
    # via an explicit target before multi-user.target.
    systemd.targets.image-mounts = {
      description = "ESP and FHS bind mounts (/boot, /bin, /lib, /lib64, /usr/bin)";
      requires = [
        "boot.mount"
        "bin.mount"
        "lib.mount"
        "lib64.mount"
        "usr-bin.mount"
      ];
      after = [
        "boot.mount"
        "bin.mount"
        "lib.mount"
        "lib64.mount"
        "usr-bin.mount"
      ];
      wantedBy = [ "multi-user.target" ];
    };

    ## Build-time configuration of systemd-repart during image build
    image = {
      repart = {
        # Compress the erofs image used for /nix/store. This could
        # be further tweaked with i.e. a larger cluster size and
        # -Eedupe, but would result in longer build time and we
        # we saw diminishing returns in terms of file size.
        mkfsOptions.erofs = [
          "-zlz4"
          "-Efragments,ztailpacking"
        ];

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
          # NOTE: 31-var-lib-credentials, 32-var-lib-keylime and 40-var-lib-build
          # are NOT defined here. They are created at first boot by
          # systemd-repart (see runtime config below). This is intentional:
          # repart only formats and LUKS-encrypts partitions during creation.
          # Build-time placeholders would be left unformatted, and adjacent
          # partitions block in-place growth.
        };
      };
    };

    ## Run-time configuration of systemd-repart on first boot.

    # Persistent, TPM2-bound partitions for credentials and keylime agent state.
    # These don't exist in the build-time image — systemd-repart creates them
    # as new partitions on first boot (which triggers formatting + TPM2 LUKS
    # enrollment). On subsequent boots, repart matches them by type+label and
    # leaves them untouched (no FactoryReset).
    systemd.repart.partitions."31-var-lib-credentials" = {
      Type = "linux-generic";
      Label = "var-lib-credentials";
      Format = "ext4";
      Encrypt = "tpm2";
      SizeMinBytes = "64M";
    };
    systemd.repart.partitions."32-var-lib-keylime" = {
      Type = "linux-generic";
      Label = "var-lib-keylime";
      Format = "ext4";
      Encrypt = "tpm2";
      SizeMinBytes = "64M";
    };

    # Ephemeral build partition — factory-reset on every boot.
    systemd.repart.partitions."40-var-lib-build" = {
      Type = "var";
      Label = "var-lib-build";
      Format = "ext4";
      Encrypt = "key-file";
      SizeMinBytes = "250G";
      # Tell systemd-repart to re-format and re-encrypt this partition on each boot
      # if run with --factory-reset, which we do by default.
      FactoryReset = true;
    };

    boot.initrd.luks.devices."var_lib_credentials_crypt" = {
      device = "/dev/disk/by-partlabel/var-lib-credentials";
      crypttabExtraOpts = [ "tpm2-device=auto" ];
    };
    boot.initrd.luks.devices."var_lib_keylime_crypt" = {
      device = "/dev/disk/by-partlabel/var-lib-keylime";
      crypttabExtraOpts = [ "tpm2-device=auto" ];
    };
    boot.initrd.luks.devices."var_lib_crypt" = {
      keyFile = "/etc/disk.key";
      device = "/dev/disk/by-partlabel/var-lib-build";
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
            # only /var/lib/build in our case. The read-only partitions stay in place.
            "--factory-reset=true"
          ];
        };

        services = {
          systemd-repart = {
            before = [
              "systemd-cryptsetup@var_lib_credentials_crypt.service"
              "systemd-cryptsetup@var_lib_keylime_crypt.service"
              "systemd-cryptsetup@var_lib_crypt.service"
            ];
            after = [ "systemd-udev-settle.service" ];
            requires = [ "systemd-udev-settle.service" ];
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

          # Link the ESP to /run/systemd/volatile-root before systemd-repart
          # runs. Since "/" is tmpfs, repart can't discover the disk on its
          # own. This symlink points it at a partition that always exists in
          # the image (the ESP), so repart finds the right disk.
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
              ExecStart = "/bin/ln -sf /dev/disk/by-partlabel/${
                config.image.repart.partitions."00-esp".repartConfig.Label
              } /run/systemd/volatile-root";
            };
          };
        };
      };
  };
}
