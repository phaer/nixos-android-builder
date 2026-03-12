{
  writers,
  lib,
  binutils,
  systemd,
  runCommand,
  python3Packages,
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
      "--prefix PATH : ${
        lib.makeBinPath [
          binutils
          systemd-measure
        ]
      }"
    ];
  } (builtins.readFile ./calculate-pcr11.py);

  # Run-time tool: read PCRs from the TPM sysfs on a live machine and
  # emit a keylime tpm_policy JSON.  Displays a QR code when on a TTY.
  read-tpm-pcrs = writers.writePython3Bin "read-tpm-pcrs" {
    libraries = [ python3Packages.qrcode ];
  } (
    builtins.readFile ./read-tpm-pcrs.py
  );
}
