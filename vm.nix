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
    };

    # Upstreams system.build.vm wrapped, so that it starts the VM with a
    # copy-on-write copy of the underlying, read-only, disk image from the
    # /nix/store.
    system.build.vm =
      let
        cfg = config.virtualisation;
        hostPkgs = cfg.host.pkgs;

        runner' = hostPkgs.writeShellScript "run-${config.system.name}-vm" ''
          if [ ! -e ${cfg.diskImage} ]; then
            echo "creating ${cfg.diskImage}"
                ${cfg.qemu.package}/bin/qemu-img create \
                  -f qcow2 \
                  -b ${config.system.build.finalImage}/${config.image.fileName} \
                  -F raw \
                  ${cfg.diskImage} \
                  "${toString cfg.diskSize}M"
          else
            echo "${cfg.diskImage} already exists, skipping creation"
          fi
          ${cfg.runner} $@
        '';
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
            ln -s ${runner'} $out/bin/run-${config.system.name}-vm
          ''
      );
  };
}
