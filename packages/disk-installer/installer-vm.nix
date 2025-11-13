{ lib, config, ... }:
{
  virtualisation = {
    diskImage = "${config.system.build.image}/${config.image.filePath}";
    cores = 8;
    memorySize = 1024 * 8;
    directBoot.enable = false;
    installBootLoader = false;
    useBootLoader = true;
    useEFIBoot = true;
    mountHostNixStore = false;
    efi.keepVariables = false;

    # NixOS overrides filesystems for VMs by default
    fileSystems = lib.mkForce { };
    useDefaultFilesystems = false;

    emptyDiskImages = [
      (1024 * 300)
    ]
    ++
      lib.optionals config.nixosAndroidBuilder.artifactStorage.enable
      [
        (1024 * 10)
      ];
  };
}
