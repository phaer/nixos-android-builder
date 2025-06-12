{
  description = "A ephemeral NixOS VMs to build Android Open Source Project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = nixpkgs.lib;

    nixosModules = {
      host = ./configuration.nix;
      vm = ./vm.nix;
      epehmeral = ./ephemeral.nix;
      image = ./image.nix;
    };
    modules = lib.attrValues nixosModules;

    vm = pkgs.nixos { imports = modules; };

    run-vm = vm.config.system.build.vm;
    image = vm.config.system.build.image;
  in {
    inherit nixosModules;
    nixosConfigurations = { inherit vm; };
    packages.${system} = {
      inherit run-vm;
      inherit image;
      default = image;
    };
  };
}
