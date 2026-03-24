{
  lib,
  efivar,
  tpm2-tools,
  writers,
  callPackage,
}:
let
  measured-boot-library = callPackage ../measured-boot-library { };
  wrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    "${lib.makeBinPath [ tpm2-tools ]}"
    # libefivar is needed by tpm2_eventlog to decode UEFI device
    # paths into human-readable strings (e.g. FvVol/FvFile for
    # firmware-resident apps).  Without it, DevicePath is raw hex
    # and firmware apps cannot be distinguished from the UKI.
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    "${lib.getLib efivar}/lib"
  ];
in
{
  # CLI tool to generate the measured boot reference state from an
  # event log.  Thin wrapper around the measured_boot_state library.
  measure-boot-state = writers.writePython3Bin "measure-boot-state" {
    libraries = [ measured-boot-library ];
    makeWrapperArgs = wrapperArgs;
  } (builtins.readFile ./measure-boot-state.py);

  # Run-time tool: generate measured boot reference state from the UEFI
  # event log and report it to the auto-enrollment server.
  report-measured-boot-state = writers.writePython3Bin "report-measured-boot-state" {
    libraries = [ measured-boot-library ];
    makeWrapperArgs = wrapperArgs;
  } (builtins.readFile ./report-measured-boot-state.py);
}
