{
  lib, pkgs, ...
}: {

  config = {
    # Name our system. Image file names and metadata is derived from this
    system.name = "android-builder";

    # Target architecture of this NixOS instance
    nixpkgs.hostPlatform = { system = "x86_64-linux"; };

    # Location of the random key to encrypt the persistent volume with,
    # should never touch the disk, /etc is on tmpfs
    boot.initrd.systemd.repart.keyFile = "/etc/disk.key";

    # --factory-reset instructs systemd-repart to reset all partitions marked with FactoryReset=true,
    # only /var/lib in our case. The read-only partitions stay in place.
    boot.initrd.systemd.repart.factoryReset = true;

    # Add extra software from nixpkgs, as well as a custom shell to build Android
    environment.systemPackages = with pkgs; [
      vim htop tmux gitMinimal

      (import ./android-build-env.nix { inherit pkgs; })
    ];

    # Configure a build user
    users = {
      users."user" = {
        isNormalUser = true;
        group = "user";
        extraGroups = [ "kvm" "wheel"];
        home = "/var/lib/build";
        createHome = true;
      };
      groups.user = {};
    };

    # Configure nix with flake support, but no channels.
    nix = {
      enable = true;
      channel.enable = false;
      settings.experimental-features = ["nix-command" "flakes"];
    };

    # Opt-in into systemd-based initrd, declarative user management and networking.
    boot.initrd.systemd.enable = true;
    services.userborn.enable = true;
    networking.useNetworkd = true;

    # Add all available firmware.
    hardware.enableRedistributableFirmware = true;
    hardware.enableAllHardware = true;

    # Console on tty0 for bare-metal and serial output for VMS.
    boot.kernelParams =
      [
        "console=tty0"  "console=ttyS0,115200"
      ]
    ++ (lib.optional (
      pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64
    ) "console=ttyAMA0,115200");

    # TODO: This might be good to upstream. systemd-oomd starts too early,
    # so fails twice and spams log before succeeding.
    systemd.services."systemd-oomd".after = [ "systemd-sysusers.service" ];

    # Define a stateVersion to supress eval warnings. As we don't keep state, it's irrelevant
    system.stateVersion = "25.05";
  };
}

