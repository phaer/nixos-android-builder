# Python unit tests for measured boot policy.
#
# These are fast, pure tests that don't need a VM or TPM.
# Run with: nix build .#checks.x86_64-linux.policyTests
#
# Note: measured-boot-library tests run via the package's checkPhase
# (pytestCheckHook), not as a separate flake check.
{
  pkgs,
  keylimePackage,
}:
let
  policyDir = pkgs.callPackage ../packages/keylime-measured-boot-policy { };
in
{
  # Unit tests for the UKI measured boot policy.
  # keylime is built as a Python application, so we add its
  # site-packages and propagated dependencies to PYTHONPATH.
  policyTests =
    let
      keylimeSitePackages = "${keylimePackage}/${pkgs.python3.sitePackages}";
      pyEnv = pkgs.python3.withPackages (
        ps:
        keylimePackage.propagatedBuildInputs
        ++ [
          ps.pytest
        ]
      );
    in
    pkgs.runCommand "measured-boot-policy-tests"
      {
        nativeBuildInputs = [ pyEnv ];
      }
      ''
        export PYTHONPATH="${policyDir.policyPath}:${keylimeSitePackages}:$PYTHONPATH"
        pytest -v ${../packages/keylime-measured-boot-policy/test_measured_boot_policy.py}
        touch $out
      '';
}
