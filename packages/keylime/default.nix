{
  lib,
  python3Packages,
  fetchFromGitHub,
  gnupg,
  tpm2-tools,
  efivar,
}:
let
  version = "7.14.1";
in
python3Packages.buildPythonApplication {
  pname = "keylime";
  format = "setuptools";
  inherit version;

  src = fetchFromGitHub {
    owner = "keylime";
    repo = "keylime";
    tag = "v${version}";
    hash = "sha256-EM+h/+rAzzGcp8pT3E74INLzEDBSc1Hjtojxbm26jt0=";
  };

  build-system = with python3Packages; [
    setuptools
    jinja2
  ];

  dependencies = with python3Packages; [
    cryptography
    tornado
    pyzmq
    pyyaml
    requests
    sqlalchemy
    alembic
    packaging
    psutil
    lark
    pyasn1
    pyasn1-modules
    gpgme
    jinja2
    jsonschema
  ];

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    "${lib.makeBinPath [
      gnupg
      tpm2-tools
    ]}"
    # efivar is needed by keylime for UEFI event log parsing
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    "${lib.getLib efivar}/lib"
  ];

  patches = [
    # Check tpm2_eventlog exit code instead of stderr (benign warnings
    # from UKI EV_IPL events broke all measured boot attestation).
    ./0001-elparsing-check-tpm2_eventlog-exit-code-instead-of-s.patch
    # Use the policy's get_relevant_pcrs() for event log PCR replay
    # (PCR 11 has runtime extensions from systemd-pcrphase).
    ./0002-tpm-use-policy-s-relevant-PCRs-for-event-log-verific.patch
    # Bypass ORM cache for uefi_ref_state (same stale-cache bug
    # already fixed for ima_policy).
    ./0003-tpm_engine-bypass-ORM-cache-for-uefi_ref_state.patch
  ];

  doCheck = false;

  meta = {
    description = "TPM-based key bootstrapping and system integrity measurement system";
    homepage = "https://keylime.dev";
    changelog = "https://github.com/keylime/keylime/releases/tag/v${version}";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
