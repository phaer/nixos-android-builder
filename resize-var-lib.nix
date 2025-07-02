{
  lib,
  pkgs,
  config,
  ...
}:
{
  config = {
    boot.initrd.systemd = {
      # Run systemd-repart in initrd at boot
      repart.enable = true;
      # Add mkfs, fsck, etc for ext4 to initrd
      initrdBin = [ pkgs.e2fsprogs ];
    };

    # For the resizable variant of /var/lib, we want to start out with
    # a very small partition in the image, and add the minimum size to
    # to systemd.repart.partitions below instead, in order to resize
    # it during boot.
    image.repart.partitions."var-lib".repartConfig.SizeMinBytes = lib.mkForce "10M";

    # Reuse settings of the repart-generated image file on first boot
    systemd.repart.partitions."var-lib" = config.image.repart.partitions."var-lib".repartConfig // {
      SizeMinBytes = "250G";
      # Tell systemd-repart to re-format and re-encrypt this partition on each boot
      # if run with --factory-reset, which we do by default.
      FactoryReset = true;
      # FIXME: hack to avoid formatting for too long on large disks.
      SizeMaxBytes = "500G";
    };
  };
}
