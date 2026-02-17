{
  description = "A ephemeral NixOS VMs to build Android Open Source Project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      nixosModules = lib.pipe (builtins.readDir ./modules) [
        (lib.filterAttrs (n: v: (lib.hasSuffix ".nix" n) && v == "regular"))
        (lib.mapAttrs' (
          n: _v: {
            name = lib.removeSuffix ".nix" n;
            value = ./modules/${n};
          }
        ))
      ];

      ourModules = (lib.attrValues nixosModules) ++ [ ./configuration.nix ];

      imageModules = [
        (
          { modulesPath, ... }:
          {
            imports = [
              "${modulesPath}/image/repart.nix"
              "${modulesPath}/profiles/minimal.nix"
              "${modulesPath}/profiles/perlless.nix"
              "${modulesPath}/virtualisation/qemu-vm.nix"
            ];
          }
        )
      ]
      ++ ourModules;

      nixos = pkgs.nixos {
        nixpkgs.hostPlatform = { inherit system; };
        imports = imageModules;
      };
      run-vm = nixos.config.system.build.vmWithWritableDisk;
      image = nixos.config.system.build.finalImage;

      installerModules = [
        diskInstaller.module
        diskInstaller.vm
        nixosModules.fatal-error
        {
          diskInstaller.payload = "${nixos.config.system.build.finalImage}/${nixos.config.image.filePath}";
        }
      ];

      installer-vm = installer.config.system.build.vmWithInstallerDisk;
      installer = pkgs.nixos {
        nixpkgs.hostPlatform = { inherit system; };
        imports = installerModules;
      };
      installer-image = installer.config.system.build.image;

      secureBootScripts = pkgs.callPackage ./packages/secure-boot-scripts { };
      diskInstaller = pkgs.callPackage ./packages/disk-installer { };

      docs = pkgs.callPackage ./packages/docs {
        inherit self nixos;
      };

      keylime-agent = pkgs.callPackage ./packages/keylime-agent { };

    in
    {
      inherit nixosModules;
      nixosConfigurations = { inherit nixos installer; };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = with secureBootScripts; [
            create-signing-keys
            diskInstaller.configure
            docs.build-docs
            docs.watch-docs
            pkgs.pam_u2f
          ];
        };
      };

      packages.${system} = {
        inherit
          run-vm
          image
          installer-image
          installer-vm
          keylime-agent
          ;
        inherit (secureBootScripts) create-signing-keys;
        configure-disk-image = diskInstaller.configure;
        default = image;
      };

      checks.${system} = import ./tests/default.nix {
        inherit
          pkgs
          installerModules
          imageModules
          nixos
          ;
      };
    };
}
