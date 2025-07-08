{
  description = "A ephemeral NixOS VMs to build Android Open Source Project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
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
      };
      modules = lib.attrValues nixosModules;

      vm = pkgs.nixos { imports = modules; };

      run-vm = vm.config.system.build.vm;
      image = vm.config.system.build.image;
      android-build-env = import ./android-build-env.nix { inherit pkgs; };
    in
    {
      inherit nixosModules;
      nixosConfigurations = { inherit vm; };
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
      packages.${system} = {
        inherit run-vm;
        inherit image;
        inherit android-build-env;
        default = image;
        create-vm-disk =
          let
            cfg = vm.config.virtualisation;
          in
          pkgs.writeShellScriptBin "create-vm-disk" ''
            if [ ! -e ${cfg.diskImage} ]; then
              echo "creating ${cfg.diskImage}"
                  ${cfg.qemu.package}/bin/qemu-img create \
                    -f qcow2 \
                    -b ${image}/${vm.config.image.fileName} \
                    -F raw \
                    ${cfg.diskImage} \
                    "${toString cfg.diskSize}M"
            else
              echo "${cfg.diskImage} already exists, skipping creation"
            fi
          '';
      };
    };
}
