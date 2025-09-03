{
  pkgs,
  ...
}:
let
  # pkgs.writeShellScriptBin with bashInteractive instead of pkgsruntimeShell, so that we
  # don't get errors about the missing "complete" builtin.
  writeShellScriptBin =
    name: text:
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      text = ''
        #!/bin/bash
        ${text}
      '';
      checkPhase = ''
        ${pkgs.stdenv.shellDryRun} "$target"
      '';
      meta.mainProgram = name;
    };

  fetchAndroid = writeShellScriptBin "fetch-android" ''
    set -e
    mkdir -p $SOURCE_DIR
    cd $SOURCE_DIR
    git config --global color.ui true  # keep repo from asking
    git config --global user.email "ci@example.com"
    git config --global user.name "CI User"
    repo init \
         --partial-clone \
         --no-use-superproject \
         -b android-latest-release \
         -u https://android.googlesource.com/platform/manifest

    repo sync -c $@ || true
    repo sync -c $@
  '';

  buildAndroid = writeShellScriptBin "build-android" ''
    set -e
    cd $SOURCE_DIR
    source build/envsetup.sh || true
    lunch aosp_cf_x86_64_only_phone-aosp_current-eng
    m
  '';
in
{
  

    config = {
    environment.variables = {
      "SOURCE_DIR" = "$HOME/source";
    };
    environment.systemPackages = [
      fetchAndroid
      buildAndroid
    ];
    nixosAndroidBuilder.fhsEnv.packages = with pkgs; [
      # We just override a two deps of git-repo to include less features, but don't pull huge dependencies
      # into the closure.
      (git-repo.override {
        git = gitMinimal;
      })
      gitMinimal
      diffutils
      findutils
      curl
      binutils
      zip
      unzip
      zlib
      rsync
      libxml2
      libxslt
      fontconfig
      flex
      bison
      xorg.libX11
      mesa
      openssl
      jdk
      gnumake
      python3
    ];
  };
}
