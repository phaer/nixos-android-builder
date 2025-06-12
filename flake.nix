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

    # We wrap the upstream VM runner to pass it a pre-built
    # disk image. This ensures we are testing the disk generation
    # mechanism as well, instead of just mounting the hosts nix
    # store to the VM.
    run-vm = pkgs.writeShellScriptBin "run-vm" ''
      export NIX_DISK_IMAGE="$(pwd)/nixos.img"

      echo "generating $NIX_DISK_IMAGE"
      ${pkgs.qemu}/bin/qemu-img \
        create \
        -f qcow2 \
        -F raw \
        -b "${vm.config.system.build.image}/${vm.config.image.fileName}" \
        $NIX_DISK_IMAGE

      echo "starting vm"
      ${lib.getExe vm.config.system.build.vm}
    '';

  in {
    inherit nixosModules;
    nixosConfigurations = { inherit vm; };
    packages.${system} = {
      inherit run-vm;
      default = run-vm;
    };
    checks.${system}.vm = pkgs.nixosTest (import ./test-vm.nix { customModules = modules; });
  };
}
