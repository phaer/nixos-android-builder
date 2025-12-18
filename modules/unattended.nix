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
    echo "NOTE: The system will turn off after exiting this shell"
    echo "Build outputs are in /var/lib/artifacts"
    login user
    systemctl poweroff
  '';

  test-output = pkgs.writeShellScriptBin "test-output" ''
    set -euo pipefail
    mkdir -p /var/lib/build/source/out/target/product/
    echo "Hello World" > /var/lib/build/source/out/target/product/greeting
  '';
in
{
  options.nixosAndroidBuilder.unattendedSteps = lib.mkOption {
    description = "list of shell commands to run unattended ";
    default = [
      "fetch-android"
      "build-android"
      "copy-android-outputs"
    ];
    type = lib.types.listOf lib.types.str;
  };

  config = {
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
      test-output
    ];

    # disable gettty on tty1 and 2 (logins on tty)
    systemd.services."autovt@".enable = false;
    systemd.services."getty@tty1".enable = false;
    systemd.services."getty@tty2".enable = false;

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
        STEPS = lib.concatStringsSep "," config.nixosAndroidBuilder.unattendedSteps;
      };

      script = builtins.readFile ./unattended.sh;

    };
  };
}
