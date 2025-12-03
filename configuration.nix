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

    build = {
      repoManifestUrl = "https://android.googlesource.com/platform/manifest";
      repoBranch = "android-latest-release";
      lunchTarget = "aosp_cf_x86_64_only_phone-aosp_current-eng";
      userName = "CI User";
      userEmail = "ci@example.com";
    };
  };
}
