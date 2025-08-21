{
  description = "A ephemeral NixOS VMs to build Android Open Source Project";

  inputs = {
    nixpkgs.url = "github:phaer/nixpkgs?ref=qemu-runner";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      nixosModules = {
        host = ./configuration.nix;
        vm = ./vm.nix;
        epehmeral = ./ephemeral.nix;
        image = ./image.nix;
        resize-var-lib = ./resize-var-lib.nix;
        encrypt-var-lib = ./encrypt-var-lib.nix;
        debug = ./debug.nix;
        secure-boot = ./secure-boot.nix;
        android-build-env = ./android-build-env.nix;
      };
      modules = lib.attrValues nixosModules;

      vm = pkgs.nixos {
        nixpkgs.hostPlatform = { inherit system; };
        imports = modules;
      };

      run-vm = vm.config.system.build.vm;
      image = vm.config.system.build.finalImage;
    in
    {
      inherit nixosModules;
      nixosConfigurations = { inherit vm; };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          sbsigntool
          openssl
          efitools
        ];
      };

      packages.${system} = {
        inherit run-vm;
        inherit image;
        default = image;
      };

      checks.${system} = {
        integration = pkgs.testers.runNixOSTest (import ./tests.nix { inherit modules; });
      };
    };
}
