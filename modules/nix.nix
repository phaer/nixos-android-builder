# Enable nix with flake support, no channels.
{
  lib,
  ...
}:
{
  config = {
    nix = {
      enable = lib.mkForce true;
      channel.enable = false;
      settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };
}
