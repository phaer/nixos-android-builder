# Settings which should only be applied if run as a VM, not on bare metal.
{ lib, config, modulesPath, ...}: {
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
  config = {
    virtualisation = {
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

      qemu.drives = lib.mkForce [
        {
          deviceExtraOpts = {
            bootindex = "1";
            serial = "boot";
          };
          driveExtraOpts = {
            format = "raw";
            readonly = "on";
            cache = "writeback";
            werror = "report";
          };
          file = "${config.system.build.image}/${config.image.fileName}";
          name = "boot";
        }
        {
          deviceExtraOpts = {
            bootindex = "2";
            serial = "root";
          };
          driveExtraOpts = {
            cache = "writeback";
            werror = "report";
          };
          file = "\"$NIX_DISK_IMAGE\"";
          name = "root";
        }
      ];


      # Start a headless VM with serial console.
      graphics = false;
      #sharedDirectories.androidSource = {
      #  source = "$PRJ_ROOT/android/source";
      #  target = "/mnt/source";
      #};
    };
  };
}
