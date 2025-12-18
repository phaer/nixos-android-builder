{ lib, pkgs, ... }:

let
  targets = {
    emergency = {
      wants = [ "fatal-error.service" ];
    };
  };
  services = {
    # We want to display our error, not panic
    panic-on-fail.enable = lib.mkForce false;

    # Upstreams emergency.service would grab the whole tty in case
    # emergencyAccess is enabled.
    emergency = {
      serviceConfig = {
        ExecStartPre = lib.mkForce [ "" ];
        ExecStart = lib.mkForce [
          ""
          "${pkgs.coreutils}/bin/true"
        ];
        StandardInput = lib.mkForce "null";
        StandardOutput = lib.mkForce "null";
      };
    };

    fatal-error = {
      description = "Display a fatal error to the user";

      after = [ "systemd-udevd.service" ];
      requires = [ "systemd-udevd.service" ];
      unitConfig = {
        DefaultDependencies = "no";
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

      path = [
        pkgs.dialog
        pkgs.kbd
        pkgs.systemd
      ];

      script = ''
        chvt 2

        # Without those udevadm commands, we might not yet have keyboard input
        # if we entered the emergency target too early
        udevadm trigger --action=add
        udevadm settle --timeout=10
        dialog \
            --clear \
            --colors \
            --ok-button " Shutdown " \
            --title "Error" \
            --msgbox "$(cat /run/fatal-error || echo "Unknown error, please consult logs (ctrl+alt+f1)")" \
            10 60
        chvt 1
        systemctl --no-block poweroff
      '';
    };
  };
in
{
  boot.initrd.systemd = {
    inherit targets services;
    extraBin = {
      dialog = "${pkgs.dialog}/bin/dialog";
      chvt = "${pkgs.kbd}/bin/chvt";
    };
  };
  systemd = {
    inherit targets services;
  };
  environment.systemPackages = [
    pkgs.dialog
    pkgs.kbd
  ];
}
