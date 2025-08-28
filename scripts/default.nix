{ pkgs }:
{
  create-signing-keys = pkgs.writeShellApplication {
    name = "create-signing-keys";
    runtimeInputs = [
      pkgs.sbsigntool
      pkgs.openssl
      pkgs.efitools
      pkgs.util-linux
    ];
    text = builtins.readFile ./create-signing-keys.sh;
  };

  sign-disk-image = pkgs.writeShellApplication {
    name = "sign-disk-image";
    runtimeInputs = [
      pkgs.sbsigntool
      pkgs.jq
      pkgs.mtools
      pkgs.parted
    ];
    excludeShellChecks = [ "SC2086" ];
    text = builtins.readFile ./sign-disk-image.sh;
  };
}
