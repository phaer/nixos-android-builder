# Settings which should only be applied if run as a VM, not on bare metal.
{ lib, config, modulesPath, ...}: {
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
  config = {
    virtualisation = {
      # NixOS overrides filesystems for VMs by default
      fileSystems = lib.mkForce { };
      useDefaultFilesystems = false;
      installBootLoader = false;
      # Don't use direct boot for the VM to verify that the bootloader is working.
      useBootLoader = true;
      useEFIBoot = true;
      efi.keepVariables = false;
      directBoot.enable = false;
      mountHostNixStore = false;
      # Start a headless VM with serial console.
      graphics = false;
      #sharedDirectories.androidSource = {
      #  source = "$PRJ_ROOT/android/source";
      #  target = "/mnt/source";
      #};
    };
  };
}
