{
  writers,
}:
{
  # Run-time tool: generate measured boot reference state from the UEFI
  # event log and report it to the auto-enrollment server.
  # Used as a oneshot service on the agent side.
  report-mb-refstate = writers.writePython3Bin "report-mb-refstate" {
  } (builtins.readFile ./report-mb-refstate.py);

  # Run-time tool: read firmware PCRs from the TPM and output a keylime
  # tpm_policy JSON.  Useful for debugging and manual inspection.
  read-firmware-pcrs = writers.writePython3Bin "read-firmware-pcrs" { } (
    builtins.readFile ./read-firmware-pcrs.py
  );
}
