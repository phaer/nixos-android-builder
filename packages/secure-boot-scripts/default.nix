{
  writeShellApplication,
  sbsigntool,
  openssl,
  efitools,
  util-linux,
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
}
