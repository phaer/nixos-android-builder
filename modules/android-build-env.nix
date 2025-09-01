{
  lib,
  pkgs,
  ...
}:
let
  # The default glibc build shipping with NixOS includes a dynamic linker (ld.so) that works
  # for NixOS, but ignores conventional FHS directories, such as /lib, by design.

  glibc = pkgs.callPackage ../glibc-vanilla.nix { };
  bash = pkgs.bash.override {
    interactive = true;
    forFHSEnv = true;
  };

  # A sorted list of packages to add first, so that they "win" if there are collisions/conflicts
  # during creation of the FHS env. Unresolved collisions will produce a warning in the build log.
  pins = [
    # We always want our custom builds to win
    glibc
    bash
    # These are dependencies of packages below, where multiple builds with different parameters
    # ended up in the build closure. So we pin known-good packages here.
    pkgs.binutils
    pkgs.libgcc
    pkgs.systemdMinimal
    pkgs.zstd.bin
    pkgs.getent
    pkgs.gmp
  ];

  # Packages needed to build Android AOSP. This is mostly copied from AOSP documentation, but could
  # probably be reduced further, as AOSP repos ship much of it in-tree (i.e. python3, jdk, etc)
  packages = with pkgs; [
    # Our custom builds must be included here as well, so they end up in the closure.
    # The rest of the pins above a transistive dependencies, which are implicitly included here.
    bash
    glibc
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

  storePaths = "${pkgs.closureInfo { rootPaths = packages; }}/store-paths";
  fhsEnv = (import ../fhsenv.nix { inherit pkgs; }) { inherit pins storePaths; };

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
  disabledModules = [
    # Allows symlinking /lib/ld-linux.so.2 & friends, but we need a real binary
    # - no link - there. If its options are set to `null`, upstreams `ldso`
    # module will add a tmpfiles rule to remove anything at /lib/ld-linux.so.2.
    # Even though this fails as /lib is read-only at run-time, that causes an
    # error in the system log. So we disable the `ldso` module.
    "config/ldso.nix"
  ];
  options =
    let
      # Mock ldso.nix options, so that we don't have to disable a bunch of modules
      # which are "disabled" but still evaluated by default (nix-ld, ld-stub, etc)
      mock = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };
    in
    {
      environment.ldso = mock;
      environment.ldso32 = mock;
    };
  config = lib.mkMerge [
    {
      system.build.fhsEnv = fhsEnv;
      fileSystems."/bin" = {
        device = "${fhsEnv}/bin";
        options = [ "bind" ];
        fsType = "none";
      };

      fileSystems."/lib" = {
        device = "${fhsEnv}/lib";
        options = [ "bind" ];
        fsType = "none";
      };

      fileSystems."/lib64" = {
        device = "${fhsEnv}/lib";
        options = [ "bind" ];
        fsType = "none";
      };
    }
    {
      environment.variables = {
        "PATH" = "$PATH:/bin";
        "SOURCE_DIR" = "$HOME/source";
      };
      environment.systemPackages = [
        fetchAndroid
        buildAndroid
      ];
    }
  ];
}
