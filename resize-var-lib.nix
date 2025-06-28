{ lib, pkgs, config, ...}:
{
  config = lib.mkIf (config.boot.initrd.systemd.repart.device != null) {
    boot.initrd.systemd = {
      # Run systemd-repart in initrd at boot
      repart.enable = true;
      # Add mkfs, fsck, etc for ext4 to initrd
      initrdBin = [ pkgs.e2fsprogs ];
    };

    # Use the very same configuration as for the repart-generated image file on first boot
    systemd.repart.partitions."var-lib" = config.image.repart.partitions."var-lib".repartConfig // {
      # FIXME: hack to avoid formatting for too long on large disks.
      SizeMaxBytes = "300G";
    };
  };
}

