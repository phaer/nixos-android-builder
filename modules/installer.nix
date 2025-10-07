{
  lib,
  pkgs,
  ...
}:
let
  disk-installer = pkgs.callPackage ../packages/disk-installer { };
in
{
  boot.initrd.systemd = {
    contents."/etc/terminfo".source = "${pkgs.ncurses}/share/terminfo";

    initrdBin = [ pkgs.parted disk-installer.run ];
    extraBin = {
      lsblk = "${pkgs.util-linux}/bin/lsblk";
      tee = "${pkgs.coreutils}/bin/tee";
      jq = "${pkgs.jq}/bin/jq";
      ddrescue = "${pkgs.ddrescue}/bin/ddrescue";
      dialog = "${pkgs.dialog}/bin/dialog";
      systemd-cat = "${pkgs.systemdMinimal}/bin/systemd-cat";
      chvt = "${pkgs.kbd}/bin/chvt";
    };

    # keep /var/lib from timing out during installer run
    units."dev-disk-by\\x2dpartlabel-var\\x2dlib.device.d/timeout.conf" = {
      text = ''
        [Unit]
        JobTimeoutSec=Infinity
      '';
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
          "systemd-cryptsetup@var\\x2dlib.service"
        ];

        wants = [ "initrd-root-device.target" ];
        wantedBy = [ "initrd-root-fs.target" ];

        unitConfig = {
          DefaultDependencies = false;
          ConditionPathExists = "/boot/install_target";
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardInput = "tty-force";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/tty2";
          TTYReset = true;
          Restart = "no";
        };

        onFailure = [ "fatal-error.target" ];
        script = lib.getExe disk-installer.run;
      };
    };
  };
}
