# UKI-aware measured boot policy for keylime.
#
# Provides:
# - policyPath: directory containing the policy module, to be added to
#   PYTHONPATH so the verifier can import it via measured_boot_imports.
# - create-uki-refstate: generates reference state from a UEFI event log.
{
  lib,
  python3Packages,
  tpm2-tools,
  runCommand,
  writers,
}:
{
  # Directory containing the policy module. Add to the verifier's
  # PYTHONPATH and reference as "uki_policy" in measured_boot_imports.
  policyPath = runCommand "keylime-uki-policy" { } ''
    mkdir -p $out
    cp ${./uki_policy.py} $out/uki_policy.py
  '';

  # CLI tool to generate the UKI reference state from an event log.
  # Parses the event log directly with tpm2_eventlog + PyYAML,
  # without depending on the full keylime Python package.
  create-uki-refstate = writers.writePython3Bin "create-uki-refstate" {
    libraries = [ python3Packages.pyyaml ];
    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      "${lib.makeBinPath [ tpm2-tools ]}"
    ];
  } (builtins.readFile ./create_uki_refstate.py);
}
