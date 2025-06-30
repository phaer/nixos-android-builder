{ lib, config, pkgs, ...}: let
in {
  config = {
    systemd.repart.partitions."var-lib".Encrypt = "key-file";

    boot.initrd.luks.devices."var-lib-crypt" = {
      keyFile = config.boot.initrd.systemd.repart.keyFile;
      device = "/dev/disk/by-partlabel/var-lib";
    };

    fileSystems."/var/lib".device = lib.mkForce "/dev/mapper/var-lib-crypt";

    boot.initrd.systemd.services.generate-disk-key = {
      description = "Generate a secure, ephemeral key to encrypt the persistent disk with";
      wantedBy = [ "initrd.target" ];
      before = [ "systemd-repart.service" "systemd-cryptsetup@var\x2dlib\x2dcrypt.service" ];
      requiredBy = ["systemd-repart.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "generate-disk-key" ''
          head -c 32 /dev/urandom > /etc/disk.key
          chmod 600 /etc/disk.key
        '';
      };
    };
  };
}
