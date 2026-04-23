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
    # Wrapper that sets up the environment for GNOME's Wayland session.
    # gnome-session needs XDG_SESSION_TYPE, XDG_CURRENT_DESKTOP, and a
    # D-Bus session bus before it can start Mutter as its compositor.
    environment.systemPackages = lib.mkIf config.desktop.gnome [
      (pkgs.writeShellScriptBin "gnome-wayland" ''
        export XDG_CURRENT_DESKTOP=GNOME
        . /etc/profile
        exec ${pkgs.gnome-session}/bin/gnome-session "$@"
      '')
    ];

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

    # GNOME desktop (optional).
    services.xserver.enable = lib.mkIf config.desktop.gnome true;
    services.desktopManager.gnome.enable = lib.mkIf config.desktop.gnome true;
  };
}
