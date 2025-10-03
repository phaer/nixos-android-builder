{
  pkgs,
  ...
}:
{
  boot.initrd.systemd = {
    contents."/etc/terminfo".source = "${pkgs.ncurses}/share/terminfo";

    initrdBin = [ pkgs.parted ];
    extraBin = {
      lsblk = "${pkgs.util-linux}/bin/lsblk";
      jq = "${pkgs.jq}/bin/jq";
      ddrescue = "${pkgs.ddrescue}/bin/ddrescue";
      dialog = "${pkgs.dialog}/bin/dialog";
      systemd-cat = "${pkgs.systemdMinimal}/bin/systemd-cat";
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
          StandardOutput = "tty";
          StandardError = "tty";
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
