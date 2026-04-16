# Interactive desktop configuration for building and configuring the
# other nixosConfigurations in this repository.
{
  lib,
  pkgs,
  config,
  ...
}:
{
  options.desktop = {
    gnome = lib.mkEnableOption "GNOME desktop environment";
  };

  config = {
    system.name = "desktop";

    # Always include basic interactive tools.
    environment.systemPackages = with pkgs; [
      vim
      htop
      tmux
      gitMinimal
    ];

    # Set an empty password for "user" — interactive machine.
    users.users."user".initialHashedPassword = "";

    # Allow password-less sudo for wheel users.
    security.sudo.wheelNeedsPassword = false;

    # YubiKey groups — override in a machine-specific config.
    # Generate keys with:
    #   pamu2fcfg -N -i "pam://nixos-android-builder" -o "pam://nixos-android-builder" -u "user"
    nixosAndroidBuilder.yubikeys.groupA = lib.mkDefault [ ];
    nixosAndroidBuilder.yubikeys.groupB = lib.mkDefault [ ];

    # Enable DHCP on all interfaces.
    networking.useNetworkd = true;
    systemd.network.networks."40-wired" = {
      matchConfig.Type = "ether";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
    };

    # GNOME desktop (optional).
    services.xserver.enable = lib.mkIf config.desktop.gnome true;
    services.desktopManager.gnome.enable = lib.mkIf config.desktop.gnome true;
    services.displayManager.gdm = lib.mkIf config.desktop.gnome {
      enable = true;
      autoLogin.delay = 5;
    };
    services.displayManager.autoLogin = lib.mkIf config.desktop.gnome {
      enable = true;
      user = "user";
    };
    # Workaround: GNOME auto-login + Wayland needs this.
    systemd.services."getty@tty1".enable = lib.mkIf config.desktop.gnome false;
    systemd.services."autovt@tty1".enable = lib.mkIf config.desktop.gnome false;
  };
}
