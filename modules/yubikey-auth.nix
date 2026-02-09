{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.nixosAndroidBuilder.yubikeys.groupA = lib.mkOption {
    description = ''
      list of u2f (i.e. yubikeys) public keys for pam, as output by pamu2fcfg

      pamu2fcfg -N -i "pam://nixos-android-builder" -o "pam://nixos-android-builder" -u "user"
    '';
    type = lib.types.listOf lib.types.str;
  };

  options.nixosAndroidBuilder.yubikeys.groupB = lib.mkOption {
    description = ''
      list of u2f (i.e. yubikeys) public keys for pam, as output by pamu2fcfg

      pamu2fcfg -N -i "pam://nixos-android-builder" -o "pam://nixos-android-builder" -u "user"
    '';
    type = lib.types.listOf lib.types.str;
  };

  config = {
    environment.etc.u2f_mappings_groupA.text = lib.concatStringsSep "\n" config.nixosAndroidBuilder.yubikeys.groupA;
    environment.etc.u2f_mappings_groupB.text = lib.concatStringsSep "\n" config.nixosAndroidBuilder.yubikeys.groupB;

    security.pam.u2f = {
      enable = true;
    };

    security.pam.services.login.text = ''
      # Account management.
      account required ${pkgs.pam}/lib/security/pam_unix.so

      # Authentication management.
      auth required ${pkgs.pam_u2f}/lib/security/pam_u2f.so authfile=/etc/u2f_mappings_groupA interactive [prompt=Insert Yubikey for Group A, then press Enter before touching that Yubikey.] origin=pam://nixos-android-builder appid=pam://nixos-android-builder
      auth required ${pkgs.pam_u2f}/lib/security/pam_u2f.so authfile=/etc/u2f_mappings_groupB interactive [prompt=Insert Yubikey for Group B, then press Enter before touching that Yubikey.] origin=pam://nixos-android-builder appid=pam://nixos-android-builder

      # Session management.
      session required ${pkgs.pam}/lib/security/pam_env.so conffile=/etc/pam/environment readenv=0
      session required ${pkgs.pam}/lib/security/pam_unix.so
      session required ${pkgs.pam}/lib/security/pam_loginuid.so
      session optional ${config.systemd.package}/lib/security/pam_systemd.so
    '';

    security.pam.services.su = {
        u2fAuth = true;
        unixAuth = false; # Disable password authentication
    };

    # allow no passwords set.
    users.allowNoPasswordLogin = true;
  };
}
