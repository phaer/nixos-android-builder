{
  pkgs,
  ...
}:
{
  boot.initrd.systemd = {
    initrdBin = [ pkgs.parted ];
    extraBin = {
      lsblk = "${pkgs.util-linux}/bin/lsblk";
      blockdev = "${pkgs.util-linux}/bin/blockdev";
      pv = "${pkgs.pv}/bin/pv";
      jq = "${pkgs.jq}/bin/jq";
      ddrescue = "${pkgs.ddrescue}/bin/ddrescue";
      dialog = "${pkgs.dialog}/bin/dialog";
    };

    services = {
      disk-installer = {
        description = "Early user prompt during initrd";

        after = [
          "initrd-root-device.target"
          "boot.mount"
          "ensure-secure-boot-enrollment.service"
        ];
        before = [
          "initrd-root-fs.target"
          "systemd-repart.service"
          "generate-disk-key.service"
          "sysroot.mount"
          "sysusr-usr.mount"
        ];
        wants = [ "initrd-root-device.target" ];
        wantedBy = [ "initrd-root-fs.target" ];

        unitConfig = {
          DefaultDependencies = false;
          OnFailure = "halt.target";
          ConditionPathExists = "/boot/install_target";
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardInput = "tty-force";
          StandardOutput = "journal+console";
          StandardError = "journal+console";
          TTYPath = "/dev/console";
          TTYReset = true;
          TTYVHangup = true;
          TTYVTDisallocate = true;
        };

        script = builtins.readFile ./installer.sh;
      };
    };
  };
}
