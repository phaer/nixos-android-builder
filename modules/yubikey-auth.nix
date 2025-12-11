{
  lib,
  config,
  ...
}:
{
  options.nixosAndroidBuilder.yubikeys = lib.mkOption {
    description = ''
      list of u2f (i.e. yubikeys) public keys for pam, as output by pamu2fcfg

      pamu2fcfg -N --pin-verification -i "pam://nixos-android-builder" -o "pam://nixos-android-builder" -u "user"
    '';
    type = lib.types.listOf lib.types.str;
  };
  config = {
    environment.etc.u2f_mappings.text = lib.concatStringsSep "\n" config.nixosAndroidBuilder.yubikeys;

    security.pam.u2f = {
      enable = true;
      settings = {
        authfile = "/etc/u2f_mappings";
        cue = true;
        origin = "pam://nixos-android-builder";
        appid = "pam://nixos-android-builder";
      };
    };

    security.pam.services.login = {
      u2fAuth = true;
      unixAuth = false; # Disable password authentication
    };

    # allow no passwords set.
    users.allowNoPasswordLogin = true;
  };
}
