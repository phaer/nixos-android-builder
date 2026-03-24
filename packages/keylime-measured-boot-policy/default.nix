# Measured boot policy for keylime (UKI boot chain).
#
# Provides:
# - policyPath: directory containing the policy module, to be added to
#   PYTHONPATH so the verifier can import it via measured_boot_imports.
{
  runCommand,
}:
{
  # Directory containing the policy module. Add to the verifier's
  # PYTHONPATH and reference as "measured_boot_policy" in
  # measured_boot_imports.
  policyPath = runCommand "keylime-measured-boot-policy" { } ''
    mkdir -p $out
    cp ${./measured_boot_policy.py} $out/measured_boot_policy.py
  '';
}
