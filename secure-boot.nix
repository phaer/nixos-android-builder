{ pkgs, ... }:
let
  enroll-secure-boot = pkgs.writeShellScriptBin "enroll-secure-boot" ''
    set -xeu
    # allow modification of efivars
    sudo chattr -i /sys/firmware/efi/efivars/db-*
    sudo chattr -i /sys/firmware/efi/efivars/KEK-*

    # append the new certificates (keeping the microsoft certs)
    sudo efi-updatevar -a -c /boot/EFI/keys/db.crt db
    sudo efi-updatevar -a -c /boot/EFI/keys/KEK.crt KEK

    # install PK (Leaving setup mode and enters user mode)
    sudo efi-updatevar -f /boot/EFI/keys/PK.auth PK
  '';
in
{
  # debug tooling
  environment.systemPackages = [
    pkgs.efitools
    enroll-secure-boot
  ];
}
