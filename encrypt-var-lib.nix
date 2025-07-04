{ lib, config, ...}: {
  config = {
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
      requiredBy = ["systemd-repart.service" ];
      unitConfig = {
        DefaultDependencies = false;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = ''/bin/sh -c "umask 0077; head -c 64 /dev/urandom > /etc/disk.key"'';
      };
    };

    # Link the read-only nix store to /run/systemd/volatile-root before
    # systemd-repart runs. systemd-repart normally looks for the block device
    # backing "/", or this path. So this enables systemd-repart to find the
    # right device at boot.
    boot.initrd.systemd.services.link-volatile-root = {
      description = "Create volatile-root to tell systemd-repart which disk to user";
      wantedBy = [ "initrd.target" ];
      before = [ "systemd-repart.service" ];
      requiredBy = ["systemd-repart.service" ];
      unitConfig = {
        DefaultDependencies = false;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = ''/bin/ln -sf /dev/disk/by-partlabel/${config.image.repart.partitions."store".repartConfig.Label} /run/systemd/volatile-root'';
      };
    };
  };
}
