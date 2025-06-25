{
  lib, pkgs, ...
}: {

  config = {
    nixpkgs.hostPlatform = { system = "x86_64-linux"; };
    system.stateVersion = "25.05";

    system.name = "android-builder";


    environment.systemPackages = with pkgs; [
      vim htop tmux gitMinimal

      (import ./android-build-env.nix { inherit pkgs; })
    ];

    users = {
      users."user" = {
        initialHashedPassword = "";
        isNormalUser = true;
        group = "user";
        extraGroups = [ "kvm" "wheel"];
        home = "/var/lib/build";
        createHome = true;
      };
      groups.user = {};
    };

    # Allow root to login without password
    users.users.root.initialHashedPassword = "";

    # Allow password-less sudo for wheel users
    security.sudo.wheelNeedsPassword = false;

    # Auto-login user
    services.getty.autologinUser = "user";

    nix = {
      enable = true;
      channel.enable = false;
      settings.experimental-features = ["nix-command" "flakes"];
    };

    boot.loader.systemd-boot.enable = true;
    boot.initrd.systemd.enable = true;
    services.userborn.enable = true;
    networking.useNetworkd = true;

    # Add available, freely licensed firmware.
    hardware.enableRedistributableFirmware = true;

    # Enable unauthenticated shell if early boot fails
    boot.initrd.systemd.emergencyAccess = true;


    boot.kernelParams =
      [
        # Add verbose log output, to aid debugging boot issues. log_level=debug is available as well.
        "systemd.show_status=true"
        "systemd.log_level=info"
        "systemd.log_target=console"
        "systemd.journald.forward_to_console=1"

        # Console on tty0 and serial output.
        "console=tty0"  "console=ttyS0,115200"
      ]
    ++ (lib.optional (
      pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64
    ) "console=ttyAMA0,115200");

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ohci_pci"
    "usb_storage"
    "sd_mod"
    "vfat"
    "ext4"
    "erofs"
  ];

    # TODO: This might be good to upstream. systemd-oomd starts too early,
    # so fails twice and spams log before succeeding.
    systemd.services."systemd-oomd".unitConfig.After = "systemd-sysusers.service";

  };
}

