# Python unit tests for measured boot policy and library.
#
# These are fast, pure tests that don't need a VM or TPM.
# Run with: nix build .#checks.x86_64-linux.unitTests
{
  pkgs,
  keylimePackage,
}:
let
  measured-boot-library = pkgs.callPackage ../packages/measured-boot-library { };

  policyDir = pkgs.callPackage ../packages/keylime-measured-boot-policy { };
in
{
  # Unit tests for the measured boot state library
  libraryTests =
    pkgs.runCommand "measured-boot-library-tests"
      {
        nativeBuildInputs = [
          (pkgs.python3.withPackages (ps: [
            ps.pytest
            measured-boot-library
          ]))
        ];
      }
      ''
        pytest -v ${../packages/measured-boot-library/test_measured_boot_state.py}
        touch $out
      '';

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
