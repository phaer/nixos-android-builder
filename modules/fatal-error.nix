let
  targets = {
    emergency = {
      wants = [ "fatal-error.service" ];
    };
  };
  services = {
    fatal-error = {
      description = "Display a fatal error to the user";
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
      script = ''
        chvt 2
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
  boot.initrd.systemd = { inherit targets services; };
  systemd = { inherit targets services; };
}
