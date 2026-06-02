# Interactive desktop configuration for building and configuring the
# other nixosConfigurations in this repository.
{
  config = {
    system.name = "desktop";

    # Enable debug shell on tty3 and verbose boot logging.
    nixosAndroidBuilder.debug = true;

    # Basic interactive tools and passwordless sudo come from debug.nix.
    # Login greeter and session picker come from modules/desktop.nix.

    # Enroll one PIV card per group, then paste the printed SPKI values here:
    #   piv-multiparty-enroll -u user -g A
    #   piv-multiparty-enroll -u user -g B
    # entries.user = [
    #   { group = "A"; spki = "MFkw..."; }
    #   { group = "B"; spki = "MFkw..."; }
    # ];
    security.pam.multiparty.entries = { };
  };
}
