{
  writers,
}:
{
  # Run-time tool: read TPM PCRs and report them to the auto-enrollment
  # server.  Used as a oneshot service on the agent side.
  report-pcrs = writers.writePython3Bin "report-pcrs" {
  } (builtins.readFile ./report-pcrs.py);

  # Run-time tool: read firmware PCRs from the TPM and output a keylime
  # tpm_policy JSON.  Useful for debugging and manual inspection.
  read-firmware-pcrs = writers.writePython3Bin "read-firmware-pcrs" { } (
    builtins.readFile ./read-firmware-pcrs.py
  );
}
