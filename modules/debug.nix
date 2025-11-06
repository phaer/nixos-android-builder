# Support debug builds with interactive login & extra software.
{ pkgs, lib, ... }:
{
  # Add extra software from nixpkgs for convinience.
  environment.systemPackages = with pkgs; [
    vim
    htop
    tmux
    gitMinimal
  ];

  # Configure nix with flake support, but no channels.
  nix = {
    enable = lib.mkForce true;
    channel.enable = false;
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  # Set an empty password for "user"
  users.users."user" = {
    initialHashedPassword = "";
  };

  # Allow password-less sudo for wheel users
  security.sudo.wheelNeedsPassword = false;

  # Auto-login user
  services.getty.autologinUser = "user";

  # Enable unauthenticated shell if early boot fails
  boot.initrd.systemd.emergencyAccess = true;

  # Add grep to the initrd. Feel free to remove, this just makes
  # inspection and debugging in an emergency shell much more convinient.
  boot.initrd.systemd.initrdBin = [ pkgs.gnugrep ];
}
