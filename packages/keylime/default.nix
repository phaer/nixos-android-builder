{
  lib,
  python3Packages,
  fetchFromGitHub,
  gnupg,
  tpm2-tools,
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
