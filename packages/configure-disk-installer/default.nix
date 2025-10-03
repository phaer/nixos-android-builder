{
  writeShellApplication,
  jq,
  mtools,
  parted,
}:
writeShellApplication {
  name = "configure-disk-installer";
  runtimeInputs = [
    jq
    mtools
    parted
  ];
  excludeShellChecks = [ "SC2086" ];
  text = builtins.readFile ./configure-disk-installer.sh;
}
