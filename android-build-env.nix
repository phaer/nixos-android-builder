{ lib, pkgs, config, ...}:
let
  glibc-vanilla = pkgs.callPackage ./glibc-vanilla.nix {};

  packages = with pkgs; [
    # sudo apt-get install git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig
    gitMinimal
    binutils
    diffutils
    findutils
    gnupg
    flex
    bison
    zip
    curl
    zlib
    xorg.libX11
    mesa
    libxml2
    libxslt
    unzip
    fontconfig
    openssl
    # Before you can work with AOSP, you must have installations of OpenJDK, Make, Python 3, and Repo
    jdk
    gnumake
    python3
    (git-repo.override { git = gitMinimal; })
    rsync
  ];

  # pkgs.writeShellScriptBin with bashInteractive instead of pkgsruntimeShell, so that we
  # don't get errors about the missing "complete" builtin.
  writeShellScriptBin =
    name: text:
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      text = ''
        #!${pkgs.bashInteractive}/bin/bash
        ${text}
      '';
      checkPhase = ''
        ${pkgs.stdenv.shellDryRun} "$target"
      '';
      meta.mainProgram = name;
    };

    closure = pkgs.closureInfo {
      rootPaths = packages;
    };
    rsyncExe = pkgs.lib.getExe pkgs.rsync;

  libraries = pkgs.runCommandNoCC "android-libraries" {} ''
      mkdir -p $out/lib/
      for store_path in $(cat "${closure}/store-paths"); do
        test -e "$store_path/lib" && echo "$store_path/lib" || true
      done \
      | xargs -i ${rsyncExe} -r --copy-dirlinks --links --chmod "+w" "{}"/ $out/lib/


      ${rsyncExe} -r --copy-dirlinks --links --chmod "+w" ${glibc-vanilla}/lib/ $out/lib/
  '';

  fhsBash = pkgs.bash.override { interactive = true; forFHSEnv = true; };

  binaries = pkgs.runCommandNoCC "android-binaries" {} ''
    set -e
    mkdir -p $out/bin
    for store_path in $(cat "${closure}/store-paths"); do
      test -e "$store_path/bin" && echo "$store_path/bin" || true
    done \
    | xargs -i ${rsyncExe} -r --copy-links --copy-unsafe-links --chmod "+w" "{}"/ $out/bin

    install ${fhsBash}/bin/bash $out/bin/bash
    install ${fhsBash}/bin/bash $out/bin/sh

    for f in $out/bin/*; do
      if ${lib.getExe pkgs.file} $f | grep -q 'ELF.*dynamically'; then
        echo $f
        patchelf --set-rpath /lib --set-interpreter /lib/ld-linux-x86-64.so.2 "$f"
      fi
    done
  '';

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
  lib.mkMerge [
    {
      environment.variables = {
        "ANDROID_JAVA_HOME" = pkgs.jdk.home;
        "SOURCE_DIR" = "$HOME/source";
      };
      environment.systemPackages =
        packages ++ [
          fetchAndroid buildAndroid
        ];
    }
    {
      environment.variables = {
        "PATH" = "$PATH:/bin";
        # "ENVFS_RESOLVE_ALWAYS" = "1";
      };

      fileSystems."/bin" = {
        device = "${toString binaries}/bin";
        options = [ "bind" ];
        fsType = "none";
      };
    }
    {
      # environment.variables = {
      #   "NIX_LD_LIBRARY_PATH" = lib.mkForce "/lib";
      #   "NIX_LD_LOG" = "warn";
      # };
      # programs.nix-ld.enable = true;

      fileSystems."/lib" = {
        device = "${toString libraries}/lib";
        options = [ "bind" ];
        fsType = "none";
      };

      fileSystems."/lib64" = {
        device = "${toString libraries}/lib";
        options = [ "bind" ];
        fsType = "none";
      };
    }
    {
      environment.systemPackages = [
        pkgs.helix pkgs.zellij pkgs.ripgrep pkgs.fd pkgs.strace pkgs.jq
      ];

      virtualisation.forwardPorts = [
        { from = "host"; host.port = 2222; guest.port = 22; }
      ];
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLopgIL2JS/XtosC8K+qQ1ZwkOe1gFi8w2i1cd13UehWwkxeguU6r26VpcGn8gfh6lVbxf22Z9T2Le8loYAhxANaPghvAOqYQH/PJPRztdimhkj2h7SNjP1/cuwlQYuxr/zEy43j0kK0flieKWirzQwH4kNXWrscHgerHOMVuQtTJ4Ryq4GIIxSg17VVTA89tcywGCL+3Nk4URe5x92fb8T2ZEk8T9p1eSUL+E72m7W7vjExpx1PLHgfSUYIkSGBr8bSWf3O1PW6EuOgwBGidOME4Y7xNgWxSB/vgyHx3/3q5ThH0b8Gb3qsWdN22ZILRAeui2VhtdUZeuf2JYYh8L"
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCwT3A8zAcCGHNBVx0lhmz3Hhygs8XXszXqARj9QzHHs/fR3J55MTT/jk/GlmOnUzVj8RIPzzwru5J+8XgtBKU8="
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHqRNv8hueRuN4khLUQMiPVS0NqwZfX17BNXIRZJ9yRPAAAAE3NzaDpoZWxsb0BwaGFlci5vcmc="
      ];
    }
  ]
