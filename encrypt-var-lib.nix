{ lib, config, pkgs, ...}: let
  generateDiskKey = pkgs.writeShellScript "generate-disk-key" ''
    head -c 32 /dev/urandom > /etc/disk.key
    chmod 600 /etc/disk.key
  '';
in {
  config = {
    systemd.repart.partitions."var-lib".Encrypt = "key-file";

    boot.initrd.luks.devices."var-lib-crypt" = {
      keyFile = config.boot.initrd.systemd.repart.keyFile;
      device = "/dev/disk/by-partlabel/var-lib";
    };

    fileSystems."/var/lib".device = lib.mkForce "/dev/mapper/var-lib-crypt";

    boot.initrd.systemd.services.systemd-repart = {
      #conflictedBy = [
      #  "systemd-cryptsetup@var\\x2dlib\\x2dcrypt.service"
      #  "systemd-cryptsetup@.service"
      #];
      before = [
        "cryptsetup-pre.target"
      ];
      requiredBy = [
        "cryptsetup-pre.target"
        "systemd-cryptsetup@var\\x2dlib\\x2dcrypt.service"
      ];
    };


    boot.initrd.systemd.contents = {
      "/etc/systemd/system.control/sysroot-nix-.ro\\x2dstore.mount.d/overrides.conf".text = ''[Unit]
After=systemd-repart.service
Requires=systemd-repart.service
      '';
      "/etc/systemd/system.control/systemd-cryptsetup@var\\x2dlib\\x2dcrypt.service.d/overrides.conf".text = ''[Unit]
After=systemd-repart.service
Requires=systemd-repart.service
      '';
    };

    boot.initrd.systemd.storePaths = [ generateDiskKey ];
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
        ExecStart = generateDiskKey;
      };
    };

    #boot.initrd.systemd.contents = let
    #  override = "[Unit]\nRequires=systemd-repart.service\nAfter=systemd-repart.service\n";
    #in {
    #  "/etc/systemd/system.control/systemd-cryptservice@systemd-cryptsetup@var\x2dlib\x2dcrypt.service/overrides.conf".text = override;
    #  "/etc/systemd/system.control/systemd-cryptservice@systemd-cryptsetup@var-lib-crypt.service/overrides.conf".text = override;
    #}
    #;
  };
}
