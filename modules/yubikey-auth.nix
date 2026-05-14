{
  lib,
  config,
  ...
}:
let
  hasEntries = config.security.pam.multiparty.entries != { };
  replaceUnix = {
    multipartyAuth = true;
    unixAuth = false;
  };
in
{
  security.pam.multiparty = {
    enable = lib.mkDefault true;
    groups = [
      "A"
      "B"
    ];
    control = "sufficient";
  };

  security.pam.services = lib.mkIf hasEntries {
    greetd = replaceUnix;
    login = replaceUnix;
    su = replaceUnix;
  };

  users.allowNoPasswordLogin = hasEntries;

  # Bootstrap: with no entries the user has no password by default.
  # Set an empty initial password so the build doesn't fail on the
  # "locked out" assertion; operators are expected to set a real
  # password or enrol cards before production use.
  users.users.user.initialHashedPassword = lib.mkIf (!hasEntries) "";
}
