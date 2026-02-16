{
  # Name our system. Image file names and metadata is derived from this.
  system.name = "android-builder";

  nixosAndroidBuilder = {

    artifactStorage = {
      enable = true;
      contents = [
        "target/product/*"
        "source_measurement.txt"
      ];
    };

    # To get a public key, attach your yubikey and run the following command on the host:
    # pamu2fcfg --pin-verification -i "pam://nixos-android-builder" -o "pam://nixos-android-builder" -u "user"
    yubikeys.groupA = [
    ];

    yubikeys.groupB = [
    ];

    unattended.enable = true;

    build = {
      branches = [
        "android-latest-release"
      ];
      repoManifestUrl = "https://android.googlesource.com/platform/manifest";
      lunchTarget = "aosp_cf_x86_64_only_phone-aosp_current-eng";
      userName = "CI User";
      userEmail = "ci@example.com";
    };
  };
}
