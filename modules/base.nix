# Custom Options & generic NixOS configuration, that don't fit in other modules.
{
  lib,
  pkgs,
  ...
}:
{
  options.nixosAndroidBuilder = {
    debug = lib.mkEnableOption "image customizations for interactive access during run-time.";
  };
  config = {
    # All users must be declared at build-time.
    users.mutableUsers = false;

    # Configure a build user
    users = {
      users."user" = {
        isNormalUser = true;
        group = "user";
        extraGroups = [
          "kvm"
          "wheel"
        ];
        home = "/var/lib/build";
        createHome = true;
      };
      groups.user = { };
    };

    # Disable nix in non-interactive builds.
    nix.enable = lib.mkDefault false;

    # Opt-out of lastlog functionality, as it did not seem to work with our setup
    # and isn't worth investing time in in our use-case.
    security.pam.services.login.updateWtmp = lib.mkForce false;

    # Opt-in into systemd-based initrd, declarative user management and networking.
    boot.initrd.systemd.enable = true;
    services.userborn.enable = true;
    networking.useNetworkd = true;

    # Add all available firmware.
    hardware.enableRedistributableFirmware = true;
    hardware.enableAllHardware = true;

    # Console on tty0 for bare-metal and serial output for VMS.
    boot.kernelParams = [
      "console=tty0"
      "console=ttyS0,115200"
    ]
    ++ (lib.optional (
      pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64
    ) "console=ttyAMA0,115200");

    # Define a stateVersion to supress eval warnings. As we don't keep state, it's irrelevant.
    system.stateVersion = "25.05";
  };
}
