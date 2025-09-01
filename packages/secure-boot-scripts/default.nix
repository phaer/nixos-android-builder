{
  writeShellApplication,
  sbsigntool,
  openssl,
  efitools,
  util-linux,
  jq,
  mtools,
  parted,
}:
{
  create-signing-keys = writeShellApplication {
    name = "create-signing-keys";
    runtimeInputs = [
      sbsigntool
      openssl
      efitools
      util-linux
    ];
    text = builtins.readFile ./create-signing-keys.sh;
  };

  sign-disk-image = writeShellApplication {
    name = "sign-disk-image";
    runtimeInputs = [
      sbsigntool
      jq
      mtools
      parted
    ];
    excludeShellChecks = [ "SC2086" ];
    text = builtins.readFile ./sign-disk-image.sh;
  };
}
