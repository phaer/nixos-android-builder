{ lib, config, ... }:
{
  config = {
    # Location of the random key to encrypt the persistent volume with,
    # should never touch the disk, /etc is on tmpfs
    boot.initrd.systemd.repart.keyFile = "/etc/disk.key";

    # --factory-reset instructs systemd-repart to reset all partitions marked with FactoryReset=true,
    # only /var/lib in our case. The read-only partitions stay in place.
    boot.initrd.systemd.repart.factoryReset = true;

    systemd.repart.partitions."var-lib".Encrypt = "key-file";

    boot.initrd.luks.devices."var_lib_crypt" = {
      keyFile = config.boot.initrd.systemd.repart.keyFile;
      device = "/dev/disk/by-partlabel/var-lib";
    };

    fileSystems."/var/lib".device = lib.mkForce "/dev/mapper/var_lib_crypt";

    boot.initrd.systemd.services.systemd-repart = {
      before = [
        "systemd-cryptsetup@var_lib_crypt.service"
      ];
      serviceConfig.ExecStartPost = "/bin/udevadm settle -t 5";
    };

    boot.initrd.systemd.services.generate-disk-key = {
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
        ExecStart = ''/bin/sh -c "umask 0077; head -c 64 /dev/urandom > /etc/disk.key"'';
      };
    };
  };
}
