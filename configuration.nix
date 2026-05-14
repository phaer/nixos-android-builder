{
  # Name our system. Image file names and metadata is derived from this.
  system.name = "android-builder";

  security.pam.multiparty.entries = { };

  nixosAndroidBuilder = {
    debug = false;

    artifactStorage = {
      enable = true;
      contents = [
        "target/product/*"
        "source_measurement.txt"
      ];
    };
    credentialStorage.enable = true;

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
