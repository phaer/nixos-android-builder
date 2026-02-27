{
  config,
  pkgs,
  lib,
  ...
}:
let
  pcrPolicy = pkgs.callPackage ../packages/pcr-policy { };

  # Pre-calculate the expected PCR 11 value from the UKI at build time.
  # Placed on the ESP (not in /nix/store) to avoid a circular dependency:
  # /etc → store partition → UKI → expectedPcr11 → /etc would be infinite.
  # The ESP already contains the UKI so referencing it here is safe.
  expectedPcr11 = pkgs.runCommand "expected-pcr11" { } ''
    ${lib.getExe pcrPolicy.calculate-pcr11} \
      ${config.system.build.uki}/${config.system.build.uki.name} \
      > $out
  '';

  enroll-secure-boot = pkgs.writeShellScriptBin "enroll-secure-boot" ''
    set -xeu
    # Allow modification of efivars
    find \
      /sys/firmware/efi/efivars/ \
      \( -name "db-*" -o -name "KEK-*" \) \
      -exec chattr -i {} \;
    esp_keystore="/boot/KEYS"
    # Append the new allowed signatures, but keep Microsofts and other vendors signatures.
    efi-updatevar -a -f "$esp_keystore/db.auth" db
    # Install Key Exchange Key
    efi-updatevar -f "$esp_keystore/KEK.auth" KEK
    # Install Platform Key (Leaving setup mode and enters user mode)
    efi-updatevar -f "$esp_keystore/PK.auth" PK
    rm -rf $esp_keystore
  '';

  ensureSecureBootEnrollment = pkgs.writeShellScript "ensure-secure-boot-enrollment" ''
    set -eu

    sb_status="$(bootctl 2>/dev/null \
    | awk '/Secure Boot:/ {print $3 " " $4}')"

    if [ "$sb_status" = "disabled (setup)" ]
    then
      echo "Secure Boot in Setup Mode, enrolling" | systemd-cat -p info
      ${lib.getExe enroll-secure-boot}
      echo "enrolled. Rebooting..." | systemd-cat -p info
      systemctl --no-block reboot
    elif [ "$sb_status" = "enabled (user)" ]
    then
      echo "Secure Boot active" | systemd-cat -p info
    else
      msg_error="Secure Boot is neither active nor in setup mode. Please enable it in firmware settings."
      echo "$msg_error" | systemd-cat -p crit
      echo "$msg_error" > /run/fatal-error
      exit 1
    fi
  '';

in
{
  environment.systemPackages = [
    pkgs.efitools
    pkgs.tpm2-tools
    enroll-secure-boot
    pcrPolicy.read-firmware-pcrs
  ];

  # Expose the expected PCR 11 hash as a build output.
  #
  # It can't be baked into the store partition or ESP at image build
  # time because that would create a circular dependency
  # (store → UKI → expectedPcr11 → store). Instead it is:
  #   1. Written to the ESP by configure-disk-image (post-build)
  #   2. Symlinked to /etc/pcr-policy/expected-pcr11 at boot
  #
  # This lets read-firmware-pcrs --verify-pcr11 compare the
  # running TPM state against the build-time expectation.
  system.build.expectedPcr11 = expectedPcr11;

  # Symlink the ESP file to /etc so read-firmware-pcrs finds it
  # at a well-known path regardless of where /boot is mounted.
  systemd.tmpfiles.rules = [
    "d /etc/pcr-policy 0755 root root -"
    "L+ /etc/pcr-policy/expected-pcr11 - - - - /boot/expected-pcr11"
  ];

  # Enable PCR phase measurements (systemd-pcrextend extends PCR 11 with boot
  # phase strings so that the final value is only reachable after a full,
  # successful boot of this exact UKI).
  systemd.additionalUpstreamSystemUnits = [
    "systemd-pcrphase-sysinit.service"
    "systemd-pcrphase.service"
  ];

  boot.initrd.supportedFilesystems.vfat = true;
  boot.initrd.systemd = {
    initrdBin = [
      pkgs.gawk
      pkgs.efitools
    ];

    storePaths = [
      enroll-secure-boot
      ensureSecureBootEnrollment
    ];

    mounts =
      let
        esp = config.image.repart.partitions."00-esp".repartConfig;
      in
      [
        {
          where = "/boot";
          what = "/dev/disk/by-partlabel/${esp.Label}";
          type = esp.Format;
          unitConfig = {
            DefaultDependencies = false;
          };
          requiredBy = [ "initrd-fs.target" ];
          before = [ "initrd-fs.target" ];
        }
      ];

    services = {
      ensure-secure-boot-enrollment = {
        description = "Ensure secure boot is active. If setup mode, enroll. if disabled, show error";
        wantedBy = [ "initrd.target" ];
        before = [
          "systemd-repart.service"
        ];
        unitConfig = {
          AssertPathExists = "/boot/KEYS";
          RequiresMountsFor = [
            "/boot"
          ];
          DefaultDependencies = false;
          OnFailure = "emergency.target";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = ensureSecureBootEnrollment;
        };
      };
    };
  };
}
