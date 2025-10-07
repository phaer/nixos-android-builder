{
  config,
  pkgs,
  lib,
  ...
}:
let
  enroll-secure-boot = pkgs.writeShellScriptBin "enroll-secure-boot" ''
    set -xeu
    # Allow modification of efivars
    find \
      /sys/firmware/efi/efivars/ \
      \( -name "db-*" -o -name "KEK-*" \) \
      -exec chattr -i {} \;
    esp_keystore="/boot/EFI/KEYS"
    # Append the new allowed signatures, but keep Microsofts and other vendors signatures.
    efi-updatevar -a -f "$esp_keystore/db.auth" db
    # Install Key Exchange Key
    efi-updatevar -f "$esp_keystore/KEK.auth" KEK
    # Install Platform Key (Leaving setup mode and enters user mode)
    efi-updatevar -f "$esp_keystore/PK.auth" PK
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
      systemctl isolate fatal-error.target
    fi
  '';

in
{
  environment.systemPackages = [
    pkgs.efitools
    enroll-secure-boot
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

    targets.fatal-error = {
      description = "Display a fatal error to the user";
      unitConfig = {
        DefaultDependencies = "no";
        AllowIsolate = "yes";
      };
      wants = [ "fatal-error.service" ];
      before = [ "initrd-root-fs.target" ];
    };

    services = {
      ensure-secure-boot-enrollment = {
        description = "Ensure secure boot is active. If setup mode, enroll. if disabled, show error";
        wantedBy = [ "initrd.target" ];
        before = [
          "systemd-repart.service"
          "disk-installer.service"
        ];
        unitConfig = {
          AssertPathExists = "/boot/EFI/KEYS";
          RequiresMountsFor = [
            "/boot"
          ];
          DefaultDependencies = false;
          OnFailure = "fatal-error.target";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = ensureSecureBootEnrollment;
        };
      };

      fatal-error = {
        description = "Display a fatal error to the user";
        unitConfig = {
          DefaultDependencies = "no";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardInput = "tty-force";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/tty2";
          TTYReset = true;
          Restart = "no";
        };
        script = ''
          chvt 2
          dialog \
          --clear \
          --colors \
          --ok-button " Shutdown " \
          --title "Error" \
          --msgbox "$(cat /run/fatal-error || echo "Unknown error, please consult logs (ctrl+alt+f1)")" \
          10 60

          chvt 1
          systemctl --no-block poweroff
        '';
      };
    };
  };
}
