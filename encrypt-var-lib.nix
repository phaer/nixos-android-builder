{
  lib,
  config,
  pkgs,
  ...
}:
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
  config = {
    systemd.repart.partitions."30-var-lib".Encrypt = "key-file";

    boot.initrd.luks.devices."var_lib_crypt" = {
      keyFile = config.boot.initrd.systemd.repart.keyFile;
      device = "/dev/disk/by-partlabel/var-lib";
    };

    fileSystems."/var/lib".device = lib.mkForce "/dev/mapper/var_lib_crypt";

    boot.initrd.systemd = {
      # Location of the random key to encrypt the persistent volume with,
      # should never touch the disk, /etc is on tmpfs
      repart.keyFile = "/etc/disk.key";

      # --factory-reset instructs systemd-repart to reset all partitions marked with FactoryReset=true,
      # only /var/lib in our case. The read-only partitions stay in place.
      repart.factoryReset = true;

      extraBin = {
        partprobe = "${pkgs.parted}/bin/partprobe";
      };

      storePaths = [
        waitForDisk
        generateDiskKey
      ];

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
      };
    };
  };
}
