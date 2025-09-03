{ lib, ... }:
{
  disabledModules = [
    # ldso.nix allows symlinking /lib/ld-linux.so.2 & friends, but we need a
    # real binary - no link - there. If its options are set to `null`,
    # upstreams `ldso` module will add a tmpfiles rule to remove anything at
    # /lib/ld-linux.so.2.
    # Even though this fails as /lib is read-only at run-time, that causes an
    # error in the system log. So we disable the `ldso` module.
    "config/ldso.nix"
  ];
  options =
    let
      # Mock ldso.nix options, so that we don't have to disable a bunch of modules
      # which are "disabled" but still evaluated by default (nix-ld, ld-stub, etc)
      mock = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };
    in
    {
      environment.ldso = mock;
      environment.ldso32 = mock;
    };
}
