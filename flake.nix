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
      diskInstaller = pkgs.callPackage ./packages/disk-installer { };

      build-docs = pkgs.writeShellApplication {
        name = "build-docs";
        runtimeInputs = [
          pkgs.pandoc
          pkgs.mermaid-filter
          pkgs.gitMinimal
          (pkgs.texliveSmall.withPackages (ps: [
            ps.framed
            ps.fvextra
          ]))
        ];
        text = ''
          cd "$(git rev-parse --show-toplevel 2>/dev/null)/docs"
            pandoc \
              --pdf-engine=xelatex \
              --toc \
              --standalone \
              --metadata=options_json:${optionDocs}/share/doc/nixos/options.json \
              --lua-filter=./nixos-options.lua  \
              --include-in-header=./header.tex \
              --highlight-style=./pygments.theme \
              --filter=mermaid-filter \
              --variable=linkcolor:blue \
              --variable=geometry:a4paper \
              --variable=geometry:margin=3cm \
              --output "./$1.pdf" "./$1.md"
        '';
      };

      watch-docs = pkgs.writeShellApplication {
        name = "watch-docs";
        runtimeInputs = [
          pkgs.entr
          pkgs.gitMinimal
        ];
        text = ''
          find "$(git rev-parse --show-toplevel 2>/dev/null)/docs" -name '*.md' \
          | entr -s "${build-docs}/bin/build-docs $*"
        '';
      };

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
        }).optionsJSON;

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
            diskInstaller.configure
            build-docs
            watch-docs
          ];
        };
      };

      packages.${system} = {
        inherit run-vm image;
        inherit (secureBootScripts) create-signing-keys sign-disk-image;
        configure-disk-installer = diskInstaller.configure;
        default = image;
      };

      checks.${system} = {
        integration = pkgs.testers.runNixOSTest {
          imports = [
            ./tests/integration.nix
            { _module.args = { inherit modules; }; }
          ];
        };
        installer = pkgs.testers.runNixOSTest {
          imports = [
            ./tests/installer.nix
            { _module.args = { inherit modules; }; }
          ];
        };

      };
    };
}
