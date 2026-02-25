{
  writeShellApplication,
  binutils,
  jq,
  systemd,
  tpm2-tools,
  runCommand,
}:
let
  # systemd-measure lives in systemd's lib output, not in bin.
  # Wrap it into a small derivation so writeShellApplication can
  # put it on PATH via runtimeInputs.
  systemd-measure = runCommand "systemd-measure" { } ''
    mkdir -p $out/bin
    ln -s ${systemd}/lib/systemd/systemd-measure $out/bin/systemd-measure
  '';
in
{
  # Build-time tool: calculate expected PCR 11 from a UKI file.
  # Used during `nix build` to pre-compute the hash for keylime policies.
  calculate-pcr11 = writeShellApplication {
    name = "calculate-pcr11";
    runtimeInputs = [
      binutils
      jq
      systemd-measure
    ];
    text = builtins.readFile ./calculate-pcr11.sh;
  };

  # Run-time tool: read firmware PCRs from the TPM on a live machine.
  # Installed into the image so operators can record a baseline.
  read-firmware-pcrs = writeShellApplication {
    name = "read-firmware-pcrs";
    runtimeInputs = [
      tpm2-tools
    ];
    text = builtins.readFile ./read-firmware-pcrs.sh;
  };
}
