{ pkgs, ... }:
let
  enroll-secure-boot = pkgs.writeShellScriptBin "enroll-secure-boot" ''
    set -xeu
    # Allow modification of efivars
    find \
      /sys/firmware/efi/efivars/ \
      \( -name "db-*" -o -name "KEK-*" \) \
      -exec chattr -i {} \;
    esp_keystore="/boot/EFI/keys"
    # Append the new allowed signatures, but keep Microsofts and other vendors signatures.
    efi-updatevar -a -f "$esp_keystore/db.auth" db
    # Install Key Exchange Key
    efi-updatevar -f "$esp_keystore/KEK.auth" KEK
    # Install Platform Key (Leaving setup mode and enters user mode)
    efi-updatevar -f "$esp_keystore/PK.auth" PK

  '';
in
{
  environment.systemPackages = [
    pkgs.efitools
    enroll-secure-boot
  ];
}
