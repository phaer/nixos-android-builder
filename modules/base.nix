# Custom Options & generic NixOS configuration, that don't fit in other modules.
{
  lib,
  pkgs,
  ...
}:
{
  options.nixosAndroidBuilder = {
    debug = lib.mkEnableOption "image customizations for interactive access during run-time";
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
        home = "/home/user";
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

    # Enable remote attestation via keylime.  The agent uses the TPM
    # Endorsement Key as its identity (hash_ek) and auto-generates its
    # mTLS certificate on first start.  Per-deployment config (registrar
    # address, CA cert) is set in configuration.nix.
    services.keylime-agent.enable = true;

    # Add all available firmware.
    hardware.enableRedistributableFirmware = true;
    hardware.enableAllHardware = true;

    # Console font with full Unicode box-drawing support (U+2500-U+257F).
    # systemd puts the console in UTF-8 mode at boot; the kernel then maps
    # Unicode code points through the font's Unicode table.  The default
    # VGA ROM font has no entries for U+2500+, so those glyphs render as '?'.
    console = {
      font = "ter-v16n";
      packages = [ pkgs.terminus_font ];
      earlySetup = true;
    };

    # Console on tty1 for bare-metal
    boot.consoleLogLevel = lib.mkForce 0;
    boot.kernelParams = [
      "systemd.log_target=console"
      "console=tty1"
    ]
    ++ (lib.optional (
      pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64
    ) "console=ttyAMA0,115200");

    # Ensure kernel modules for various storage backends are enabled in initrd
    boot.initrd.kernelModules = [
      "virtio_blk"
      "virtio_pci"
      "vfat"
      "nls_cp437"
      "nls_iso8859-1"

      "uhci_hcd"
      "ehci_hcd"
      "xhci_hcd"
      "xhci_pci"

      "usb_storage"
      "uas"
      "usbhid"
      "thunderbolt"
      "nvme"

      "sd_mod"
      "sr_mod"

      "vfat"
      "nls_cp437"
      "nls_iso8859_1"
    ];

    # Define a stateVersion to supress eval warnings. As we don't keep state, it's irrelevant.
    system.stateVersion = "25.05";
  };
}
