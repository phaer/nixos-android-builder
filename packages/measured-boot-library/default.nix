# Shared library for parsing UEFI event logs, generating measured
# boot reference states, PCR replay, and refstate diffing.  Used
# by measure-boot-state, report-measured-boot-state, and
# debug-measured-boot-state.
{
  python3Packages,
}:
python3Packages.buildPythonPackage {
  pname = "measured-boot-library";
  version = "0.1.0";
  format = "pyproject";

  src = ./.;

  build-system = [ python3Packages.setuptools ];
  dependencies = [ python3Packages.pyyaml ];

  # No tests yet — the library is exercised via integration tests.
  doCheck = false;
}
