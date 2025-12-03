{ lib, config, ... }:
let
  user = config.users.users.user;
in
{
  options.nixosAndroidBuilder.unattendedSteps = lib.mkOption {
    description = "list of shell commands to run unattended ";
    default = [ "fetch-android" "build-android" "copy-android-outputs" ];
    type = lib.types.listOf lib.types.str;
  };

  config = {
    #boot.kernelParams = [
    #  "systemd.debug_shell=tty3"
    #  "rd.systemd.debug_shell=tty3"
    #];

    # disable getty (logins on tty)
    systemd.targets.getty.enable = false;

    # allow no passwords set.
    users.allowNoPasswordLogin = true;

    systemd.services.nixos-android-builder = {
      description = "NixOS Android Builder";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = user.name;
        Group = user.group;
        StandardInput = "tty";
        StandardOutput = "tty";
        TTYPath = "/dev/tty2";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
        Restart = "no";
      };
      onFailure = [ "emergency.target" ];

      environment = {
        PATH = lib.mkForce "/run/current-system/sw/bin:/bin";
        HOME = user.home;
        STEPS = lib.concatStringsSep ":" config.nixosAndroidBuilder.unattendedSteps;
      };

      script = builtins.readFile ./unattended.sh;

    };
  };
}
