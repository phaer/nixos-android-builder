# Settings which should only be applied if run as a VM, not on bare metal.
{
  lib,
  config,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
  config = {
    virtualisation = {
      diskSize = 300 * 1024;
      memorySize = 64 * 1024;
      cores = 32;

      useSecureBoot = true;

      # Don't use direct boot for the VM to verify that the bootloader is working.
      directBoot.enable = false;
      installBootLoader = false;
      useBootLoader = true;
      useEFIBoot = true;
      mountHostNixStore = false;
      efi.keepVariables = false;

      # NixOS overrides filesystems for VMs by default
      fileSystems = lib.mkForce { };
      useDefaultFilesystems = false;

      # Start a headless VM with serial console.
      graphics = false;

      # Use a raw image, not image for the vm (for easier post-processing with mtools & such).
      diskImage = config.image.fileName;
    };

    # Upstreams system.build.vm wrapped, so that it copies the read-only
    # image out of the nix store, to a writable copy in $PWD. It then
    # signs an EFI app inside the images ESP and copies SecureBoot keys
    # to it, before it starts the VM.
    system.build.vm =
      let
        cfg = config.virtualisation;
        hostPkgs = cfg.host.pkgs;

        scripts = import ./scripts { pkgs = hostPkgs; };

        # Create a set of private keys for VM tests, but cache them in the /nix/store,
        # so we don't need to create a new pair on each run.
        testKeys = hostPkgs.runCommandLocal "test-keys" { } ''
          ${lib.getExe scripts.create-signing-keys} $out/
        '';

        runner' = hostPkgs.writeShellApplication {
          name = "run-${config.system.name}-vm";
          runtimeInputs = [
            cfg.qemu.package
          ];
          text = ''
            if [ ! -e ${cfg.diskImage} ]; then
              echo >&2 "Copying ${config.system.build.finalImage}/${config.image.fileName} to ${cfg.diskImage}"
              qemu-img convert -f raw -O raw "${config.system.build.finalImage}/${config.image.fileName}" "${cfg.diskImage}"
              echo >&2 "Resizing ${cfg.diskImage} to ${toString cfg.diskSize}M"
              qemu-img resize "${cfg.diskImage}" "${toString cfg.diskSize}M"

              echo >&2 "Signing UKI in ${cfg.diskImage}"
              if [ -n "''${testScript:-}" ]; then
                # We are supposedly running in a NixOS VM test, so we neither
                # have nor want access to production keys. Let's use test keys
                # in the world-readable nix store instead.
                echo >&2 "Using test keys to sign UKI."
                export keystore=${testKeys}
              fi
              bash ${lib.getExe scripts.sign-disk-image} "${cfg.diskImage}"
            else
              echo "${cfg.diskImage} already exists, skipping creation & signing"
            fi
            ${cfg.runner} "$@"
          '';
        };
      in
      lib.mkForce (
        hostPkgs.runCommand "nixos-vm"
          {
            preferLocalBuild = true;
            meta.mainProgram = "run-${config.system.name}-vm";
          }
          ''
            mkdir -p $out/bin
            ln -s ${config.system.build.toplevel} $out/system
            ln -s ${lib.getExe runner'} $out/bin/run-${config.system.name}-vm
          ''
      );
  };
}
