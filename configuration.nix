{
  # Name our system. Image file names and metadata is derived from this.
  system.name = "android-builder";

  nixosAndroidBuilder = {
    debug = true;

    artifactStorage = {
      enable = true;
      contents = [
        "target/product/*"
      ];
    };

    # To get a public key, attach your yubikey and run the following command on the host:
    # pamu2fcfg -N --pin-verification -i "pam://nixos-android-builder" -o "pam://nixos-android-builder" -u "user"
    yubikeys = [
      "user:arQQWVFySukz8cz1hWCKlzFgLozOYw/n2lKNfbPp2DaMsHoH0iTDIb1tvI1l1L00gb/kP1JBRExQ94r3LuXJEA==,G1hCfU7aspcfDQV589h2gH5oXggxppISiu7sAJx9aDQdpFYxyEDqTAxczbKn8bi98wLBACEq+QoM//taua4fEA==,es256,+presence+pin"
    ];

    unattendedSteps = [
      "test-output"
      "copy-android-outputs"
      "root:lock-var-lib-build"
      "root:disable-usb-guard"
      "root:start-shell"
      #"fetch-android"
      #"build-android"
      #"copy-android-outputs"
    ];

    build = {
      repoManifestUrl = "https://android.googlesource.com/platform/manifest";
      repoBranch = "android-latest-release";
      lunchTarget = "aosp_cf_x86_64_only_phone-aosp_current-eng";
      userName = "CI User";
      userEmail = "ci@example.com";
    };
  };
}
