{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  clang,
  openssl,
  tpm2-tss,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "keylime-agent";
  version = "0.2.9";

  src = fetchFromGitHub {
    owner = "keylime";
    repo = "rust-keylime";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/8ZvIhv/Z177Svv/h81zq9uz5NnPHEDA3B49Fn57Pz8=";
  };

  cargoHash = "sha256-Fg07/C3rbFeJWtvhX2UJuWmWDh4XCDuoDyEUZSsuzX8=";

  nativeBuildInputs = [
    pkg-config
    clang
  ];

  buildInputs = [
    openssl
    tpm2-tss
  ];

  env.LIBCLANG_PATH = "${lib.getLib clang.cc}/lib";

  doCheck = false;

  meta = {
    description = "Rust-based Keylime agent for TPM-based remote attestation";
    homepage = "https://keylime.dev";
    changelog = "https://github.com/keylime/rust-keylime/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "keylime_agent";
  };
})
