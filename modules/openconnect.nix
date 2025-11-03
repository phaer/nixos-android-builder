{ lib, pkgs, modulesPath, ...}:
{
  disabledModules = [
    "${modulesPath}/profiles/perlless.nix"
  ];

  config = {
    networking.useNetworkd = lib.mkForce false;
    networking.networkmanager.enable = true;
    networking.networkmanager.plugins = [ pkgs.networkmanager-openconnect ];
    environment.systemPackages = [ pkgs.networkmanager ];
  };
}
