{ pkgs }:
let
  fetchAndroid = pkgs.writeShellScriptBin "fetch-android" ''
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

    repo sync -c -j4 || true
    repo sync -c -j4
  '';
  buildAndroid = pkgs.writeShellScriptBin "build-android" ''
    set -e
    cd $SOURCE_DIR
    source build/envsetup.sh || true
    lunch aosp_cf_x86_64_only_phone-aosp_current-userdebug
    m
  '';

in
  pkgs.buildFHSEnv {
    name = "android-build-env";
    runScript = "bash";
    profile = ''
      export ANDROID_JAVA_HOME=${pkgs.jdk.home}
      export SOURCE_DIR=$HOME/source
      # We don't seem to have /lib in the linker cache by default here.
      export LD_LIBRARY_PATH=/lib
      # Set a custom prompt to more easily see in which shell we are.
      export PROMPT_COMMAND='PS1="\e[0;32mandroid-build-env\$ \e[0m"'
    '';
    targetPkgs = pkgs: with pkgs; [
      fetchAndroid
      buildAndroid
      # sudo apt-get install git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig
      gitMinimal
      binutils
      gnupg flex bison zip curl zlib xorg.libX11 mesa libxml2 libxslt unzip fontconfig openssl
      # Before you can work with AOSP, you must have installations of OpenJDK, Make, Python 3, and Repo
      jdk
      gnumake
      python3
      git-repo
      rsync
    ];
  }

