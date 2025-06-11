{
  lib, pkgs, ...
}: {

  config = {
    nixpkgs.hostPlatform = { system = "x86_64-linux"; };
    system.stateVersion = "25.05";

    environment.systemPackages = with pkgs; [ vim htop tmux gitMinimal ];

    users = {
      users."user" = {
        initialPassword = "demo";
        isNormalUser = true;
        group = "user";
        extraGroups = [ "kvm" "wheel"];
      };
      groups.user = {};
    };

    security.sudo.wheelNeedsPassword = false;
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


    boot.kernelParams =
      [ "console=tty0"  "console=ttyS0,115200" ]
    ++ (lib.optional (
      pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64
    ) "console=ttyAMA0,115200");
  };
}

