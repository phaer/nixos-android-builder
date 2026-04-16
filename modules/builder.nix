# Android-builder-specific base configuration.
#
# Options and defaults that only apply to the ephemeral android build
# system. Generic NixOS setup lives in base.nix.
{
  lib,
  ...
}:
{
  options.nixosAndroidBuilder = {
    debug = lib.mkEnableOption "image customizations for interactive access during run-time";
  };
  config = {
    # Disable nix in non-interactive builds.
    nix.enable = lib.mkDefault false;

    # Opt-out of lastlog functionality, as it did not seem to work with our setup
    # and isn't worth investing time in in our use-case.
    security.pam.services.login.updateWtmp = lib.mkForce false;

    # Enable remote attestation via keylime.  The agent uses the TPM
    # Endorsement Key as its identity (hash_ek) and auto-generates its
    # mTLS certificate on first start.  Per-deployment config (registrar
    # address, CA cert) is set in configuration.nix.
    services.keylime-agent.enable = true;
  };
}
