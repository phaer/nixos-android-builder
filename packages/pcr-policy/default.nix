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
      "--prefix PATH : ${
        lib.makeBinPath [
          binutils
          systemd-measure
        ]
      }"
    ];
  } (builtins.readFile ./calculate-pcr11.py);

  # Run-time tool: read TPM PCRs and report them to the auto-enrollment
  # server.  Used as a oneshot service on the agent side.
  report-pcrs = writers.writePython3Bin "report-pcrs" {
  } (builtins.readFile ./report-pcrs.py);
}
