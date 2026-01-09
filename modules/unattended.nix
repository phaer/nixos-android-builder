{
  lib,
  config,
  pkgs,
  ...
}:
let
  user = config.users.users.user;

  disable-usb-guard = pkgs.writeShellScriptBin "disable-usb-guard" ''
    set -euo pipefail
    systemctl stop usbguard
    for device in /sys/bus/usb/devices/*/authorized; do
      echo 1 > "$device" 2>/dev/null
    done
  '';

  lock-var-lib-build = pkgs.writeShellScriptBin "lock-var-lib-build" ''
    set -euo pipefail

    umount -v /var/lib/build
    luksDevice="$(cryptsetup status var_lib_crypt | awk '/device:/ {print $2}')"
    cryptsetup close var_lib_crypt
    cryptsetup luksKillSlot --batch-mode $luksDevice 0

    # Verify that the disk encryption key has been removed
    luksKeyslots="$(cryptsetup luksDump $luksDevice --dump-json-metadata | jq '.keyslots | length')"
    if [ $luksKeyslots = "0" ]; then
      echo "disk encryption key deleted"
    else
      echo "not all keys were deleted, there's still $luksKeyslots keys in use" | tee /run/fatal-error
      exit 1
    fi
  '';

  start-shell = pkgs.writeShellScriptBin "start-shell" ''
    set -euo pipefail
    tput sgr0
    tput ed
    echo "NOTE: The system will turn off after exiting this shell"
    echo "Build outputs are in /var/lib/artifacts"
    login user
    systemctl poweroff
  '';

in
{
  options.nixosAndroidBuilder.unattended = {
    enable = lib.mkEnableOption "unattended mode";

    steps = lib.mkOption {
      description = "list of shell commands to run unattended ";
      default = [
        "fetch-android"
        "build-android"
        "android-sbom"
        "android-measure-source"
        "copy-android-outputs"
        "root:lock-var-lib-build"
        "root:disable-usb-guard"
        "root:start-shell"
      ];
      type = lib.types.listOf lib.types.str;
    };
  };

  config = lib.mkIf config.nixosAndroidBuilder.unattended.enable {
    security.loginDefs.settings.LOGIN_TIMEOUT = 0;
    security.sudo.enable = false;
    security.doas = {
      enable = true;
      extraRules = [
        {
          users = [ "user" ];
          setEnv = [ "PATH" ];
          noPass = true;
        }
      ];
    };

    environment.systemPackages = [
      pkgs.jq
      disable-usb-guard
      lock-var-lib-build
      start-shell
    ];

    # disable gettty on tty1 and 2 (logins on tty)
    systemd.services."autovt@tty1".enable = false;
    systemd.services."autovt@tty2".enable = false;

    # filter usb devices
    services.usbguard = {
      enable = true;
      rules = ''
        # Allow HID devices
        allow with-interface equals { 03:*:* }
        # Allow USB hubs (needed for internal hubs)
        allow with-interface equals { 09:*:* }
        # Allow YubiKeys (by vendor ID)
        allow id 1050:*

        # Default block everything else
        block
      '';
    };

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
        PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:/bin";
        HOME = user.home;
        STEPS = lib.concatStringsSep "," config.nixosAndroidBuilder.unattended.steps;
      };

      script = builtins.readFile ./unattended.sh;

    };
  };
}
