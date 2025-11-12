{
  writeShellApplication,
  jq,
  mtools,
  parted,
}:
{

  module = import ./installer.nix;

  # Shell script to be run on the local machine in order to
  # pre-configure the installer for unattended installation.
  configure = writeShellApplication {
    name = "configure-disk-installer";
    runtimeInputs = [
      jq
      mtools
      parted
    ];
    excludeShellChecks = [ "SC2086" ];
    text = builtins.readFile ./configure-disk-installer.sh;
  };

  # Shell script that runs during early-boot from initrd and
  # copies itself to the target disk.
  run = writeShellApplication {
    name = "run-disk-installer";
    runtimeInputs = [
      jq
      parted
      # some dependencies are in boot.initrd.systemd.extraBin,
      # as we don't want to pull their whole store paths into the
      # initrd for just a few binaries: lsblk, ddrescue, dialog,
      # systemd-cat.
    ];
    excludeShellChecks = [ "SC2086" ];
    text = builtins.readFile ./run.sh;
  };

}
