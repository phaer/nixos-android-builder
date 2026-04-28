# Login greeter via greetd + tuigreet.
#
# Provides a session picker with U2F authentication (when keys are
# configured via yubikey-auth.nix).  Exposes the `desktop.gnome`
# option to switch between a minimal shell session and GNOME.
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
    # Git is needed for nix flake operations on the bundled source tree.
    # The gnome-wayland wrapper is only needed for the GNOME session.
    environment.systemPackages = [
      pkgs.gitMinimal
    ]
    ++ lib.optionals config.desktop.gnome [
      (pkgs.writeShellScriptBin "gnome-wayland" ''
        export XDG_CURRENT_DESKTOP=GNOME
        . /etc/profile
        exec ${pkgs.gnome-session}/bin/gnome-session "$@"
      '')
    ];

    # The desktop uses NetworkManager instead of networkd (set in base.nix).
    # NetworkManager provides DHCP, WiFi, and a UI for GNOME; it conflicts
    # with systemd-networkd so we disable the latter.
    networking.useNetworkd = lib.mkForce false;
    networking.networkmanager.enable = true;
    networking.useDHCP = lib.mkDefault true;

    # A shell session is always available as a fallback.
    services.displayManager.sessionPackages = [
      (
        (pkgs.writeTextDir "share/wayland-sessions/shell.desktop" ''
          [Desktop Entry]
          Name=Shell
          Exec=${pkgs.bashInteractive}/bin/bash
          Type=Application
        '').overrideAttrs
        { passthru.providedSessions = [ "shell" ]; }
      )
    ];

    services.greetd = {
      enable = true;
      useTextGreeter = true;
      settings.default_session = {
        command = lib.concatStringsSep " " (
          [
            "${pkgs.tuigreet}/bin/tuigreet"
            "--time"
            "--remember"
            "--remember-session"
            "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
            "--greeting 'NixOS Desktop'"
          ]
          ++ lib.optionals config.desktop.gnome [
            "--cmd gnome-wayland"
          ]
          ++ lib.optionals (!config.desktop.gnome) [
            "--cmd ${pkgs.bashInteractive}/bin/bash"
          ]
        );
        user = "greeter";
      };
    };

    # Don't auto-login with empty passwords — require U2F or explicit auth.
    security.pam.services.greetd.allowNullPassword = lib.mkForce false;

    # Tell logind the session type so pam_systemd creates a wayland
    # session (not tty). GNOME/Mutter need this to find their session.
    systemd.services.greetd.environment = lib.mkIf config.desktop.gnome {
      XDG_SESSION_TYPE = "wayland";
    };

    # PipeWire for audio (GNOME expects a working audio stack).
    services.pipewire = lib.mkIf config.desktop.gnome {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };

    # GNOME desktop (optional).
    services.desktopManager.gnome.enable = lib.mkIf config.desktop.gnome true;
  };
}
