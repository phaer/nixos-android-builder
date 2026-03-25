{
  writers,
}:
writers.writePython3Bin "attestation-ctl" {
  flakeIgnore = [ ];
} (builtins.readFile ./attestation-ctl.py)
