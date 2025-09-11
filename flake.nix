{
  description = "A ephemeral NixOS VMs to build Android Open Source Project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
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

      modules = [
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

      vm = pkgs.nixos {
        nixpkgs.hostPlatform = { inherit system; };
        imports = modules;
      };

      run-vm = vm.config.system.build.vmWithWritableDisk;
      image = vm.config.system.build.finalImage;

      secureBootScripts = pkgs.callPackage ./packages/secure-boot-scripts { };

      build-docs = pkgs.writeShellScriptBin "build-docs" ''
        cd $PRJ_ROOT/docs
        pandoc -V geometry:margin=1.5in --toc -s --lua-filter=./nixos-options.lua  -F mermaid-filter -o ./docs.pdf ./docs.md
      '';
      watch-docs = pkgs.writeShellScriptBin "watch-docs" ''
        cd $PRJ_ROOT/docs
        ls *.md | entr -s ${build-docs}/bin/build-docs
      '';

      optionDocs =
        let
          isDefinedInThisRepo =
            opt: lib.any (decl: lib.hasPrefix (toString self) (toString decl)) (opt.declarations or [ ]);
          isMocked =
            opt:
            opt.loc == [
              "environment"
              "ldso"
            ]
            ||
              opt.loc == [
                "environment"
                "ldso32"
              ];
        in
        (pkgs.nixosOptionsDoc {
          inherit (vm) options;
          transformOptions =
            opt: if isDefinedInThisRepo opt && !isMocked opt then opt else opt // { visible = false; };
        }).optionsCommonMark;

    in
    {
      inherit nixosModules;
      nixosConfigurations = { inherit vm; };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = with secureBootScripts; [
            create-signing-keys
            sign-disk-image
          ];
        };
        docs = pkgs.mkShell {
          packages = [
            pkgs.pandoc
            pkgs.mermaid-filter
            pkgs.texliveSmall
            pkgs.entr
            build-docs
            watch-docs
          ];
        };
      };

      packages.${system} = {
        inherit run-vm image optionDocs;
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
