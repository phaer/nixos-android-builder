{
  description = "A ephemeral NixOS VMs to build Android Open Source Project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
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
      modules = lib.attrValues nixosModules;

      vm = pkgs.nixos {
        nixpkgs.hostPlatform = { inherit system; };
        imports = modules ++ [ ./configuration.nix ];
      };

      run-vm = vm.config.system.build.vmWithWritableDisk;
      image = vm.config.system.build.finalImage;

      secureBootScripts = pkgs.callPackage ./packages/secure-boot-scripts { };
      build-spec = pkgs.writeShellApplication {
        name = "build-spec";
        runtimeInputs = [
          pkgs.pandoc
          pkgs.mermaid-filter
          pkgs.texliveSmall
        ];
        text = ''
          pandoc  -V geometry:margin=1.5in --toc -s  -F mermaid-filter -o SPEC.pdf SPEC.md
        '';
      };
    in
    {
      inherit nixosModules;
      nixosConfigurations = { inherit vm; };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      devShells.${system}.default = pkgs.mkShell {
        packages = with secureBootScripts; [
          create-signing-keys
          sign-disk-image
        ];
      };

      packages.${system} = {
        inherit run-vm image build-spec;
        inherit (secureBootScripts) create-signing-keys sign-disk-image;
        default = image;
      };

      checks.${system} = {
        integration = pkgs.testers.runNixOSTest {
          imports = [
            ./tests.nix
            { _module.args = { inherit modules; }; }
          ];
        };
      };
    };
}
