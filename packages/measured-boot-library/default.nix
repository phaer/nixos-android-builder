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

  # Unit tests are in test_measured_boot_state.py and run as a
  # separate flake check (checks.libraryTests) because they need
  # pytest but not tpm2_eventlog.
  doCheck = false;
}
