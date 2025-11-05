{
  lib,
  pkgs,
  config,
  ...
}:
{
  options.nixosAndroidBuilder = {
    ephemeralVarLib = lib.mkEnableOption "Use a physicial partition instead of a ramdisk for /var/lib, but re-encrypt with a throw-away key on each boot so it's effectively ephemeral";
  };

  config = lib.mkIf config.nixosAndroidBuilder.ephemeralVarLib {
    fileSystems =
      let
        parts = config.image.repart.partitions;
      in
      {
        "/var/lib" = {
          device = "/dev/mapper/var_lib_crypt";
          fsType = parts."30-var-lib".repartConfig.Format;
          neededForBoot = true;
        };
      };

    image.repart.partitions = {
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
        generateDiskKey = pkgs.writeScript "generate-disk-key" ''
          #!/bin/sh
          set -e
          umask 0077
          head -c 64 /dev/urandom > /etc/disk.key
        '';
      in
      {
        # keep /var/lib from timing out during installer run
        units."dev-disk-by\\x2dpartlabel-var\\x2dlib.device.d/timeout.conf" = {
          text = ''
            [Unit]
            JobTimeoutSec=Infinity
          '';
        };

        # We need to list our scripts here, otherwise store paths won't be in initrd
        storePaths = [
          generateDiskKey
        ];

        services = {
          systemd-repart.before = [
            "systemd-cryptsetup@var_lib_crypt.service"
          ];
          find-boot-partition.before = [
            "systemd-cryptsetup@var_lib_crypt.service"
          ];
          disk-installer.before = [
            "systemd-cryptsetup@var_lib_crypt.service"
          ];

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
        };
      };
  };
}
