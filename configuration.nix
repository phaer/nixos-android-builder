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
        initialPassword = "demo";
        isNormalUser = true;
        group = "user";
        extraGroups = [ "kvm" "wheel"];
        home = "/var/lib/build";
        createHome = true;
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

    # TODO: This might be good to upstream. systemd-oomd starts too early,
    # so fails twice and spams log before succeeding.
    systemd.services."systemd-oomd".unitConfig.After = "systemd-sysusers.service";

  };
}

