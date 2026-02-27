{
  writers,
  lib,
  binutils,
  systemd,
  runCommand,
}:
let
  # systemd-measure lives in systemd's lib output, not in bin.
  systemd-measure = runCommand "systemd-measure" { } ''
    mkdir -p $out/bin
    ln -s ${systemd}/lib/systemd/systemd-measure $out/bin/systemd-measure
  '';
in
{
  # Build-time tool: calculate expected PCR 11 from a UKI file.
  # Used during `nix build` to pre-compute the hash for keylime policies.
  calculate-pcr11 = writers.writePython3Bin "calculate-pcr11" {
    makeWrapperArgs = [
      "--prefix PATH : ${lib.makeBinPath [ binutils systemd-measure ]}"
    ];
  } (builtins.readFile ./calculate-pcr11.py);

  # Run-time tool: read firmware PCRs from the TPM sysfs on a live machine.
  # No external dependencies — reads directly from /sys/class/tpm/.
  read-firmware-pcrs = writers.writePython3Bin "read-firmware-pcrs" { }
    (builtins.readFile ./read-firmware-pcrs.py);
}
