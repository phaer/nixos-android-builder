{
  # Name our system. Image file names and metadata is derived from this.
  system.name = "android-builder";

  nixosAndroidBuilder = {

    artifactStorage = {
      enable = true;
      contents = [
        "target/product/*"
      ];
    };

    # To get a public key, attach your yubikey and run the following command on the host:
    # pamu2fcfg -N --pin-verification -i "pam://nixos-android-builder" -o "pam://nixos-android-builder" -u "user"
    yubikeys = [
    ];

    unattended = {
      enable = true;
      steps = [
        "fetch-android"
        "build-android"
        "copy-android-outputs"
      ];
    };

    build = {
      repoManifestUrl = "https://android.googlesource.com/platform/manifest";
      repoBranch = "android-latest-release";
      lunchTarget = "aosp_cf_x86_64_only_phone-aosp_current-eng";
      userName = "CI User";
      userEmail = "ci@example.com";
    };
  };
}
