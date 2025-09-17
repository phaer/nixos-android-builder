{
  pkgs,
  ...
}:
{
  boot.initrd.systemd = {
    initrdBin = [ pkgs.parted ];
    extraBin = {
      lsblk = "${pkgs.util-linux}/bin/lsblk";
      blockdev = "${pkgs.util-linux}/bin/blockdev";
      pv = "${pkgs.pv}/bin/pv";
      jq = "${pkgs.jq}/bin/jq";
      ddrescue = "${pkgs.ddrescue}/bin/ddrescue";
    };

    services = {
      disk-installer = {
        description = "Early user prompt during initrd";

        after = [
          "initrd-root-device.target"
          "boot.mount"
          "ensure-secure-boot-enrollment.service"
        ];
        before = [
          "initrd-root-fs.target"
          "systemd-repart.service"
          "generate-disk-key.service"
          "sysroot.mount"
          "sysusr-usr.mount"
        ];
        wants = [ "initrd-root-device.target" ];
        wantedBy = [ "initrd-root-fs.target" ];

        unitConfig = {
          DefaultDependencies = false;
          OnFailure = "halt.target";
          ConditionPathExists = "/boot/install_target";
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardInput = "tty-force";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/tty0";
          TTYReset = true;
          TTYVHangup = true;
          TTYVTDisallocate = true;
        };

        script = ''
          if [ ! -f /boot/install_target ]; then
            echo >&2 "/boot/install_target not found."
            exit 0
          fi

          install_source="$(
            lsblk -J -o NAME,MOUNTPOINT,PKNAME | jq -r '
              .. | objects | select(.mountpoint=="/boot") |
              "/dev/\(if .pkname then .pkname else .name end)"
            '
          )"
          if [ ! -b "$install_source" ]; then
            echo >&2 "ERROR: installation source \"$install_source\" is not a block device."
            exit 1
          fi

          install_target="$(cat /boot/install_target)"
          if [ ! -b "$install_target" ]; then
            echo >&2 "ERROR: installation target \"$install_target\" is not a block device."
            exit 1
          fi

          echo "removing /boot/install_target"
          rm /boot/install_target

          echo "unmounting /boot before copying"
          systemctl stop boot.mount

          echo "ensuring that $install_target >= $install_source."
          if ! out=$(lsblk -b -J "$install_source" "$install_target" \
            | jq -e --arg src "''${install_source#/dev/}" --arg tgt "''${install_target#/dev/}" '
              .blockdevices
              | map({(.name): .size})
              | add
              | {src: (.[ $src ]/1024/1024/1024 | round),
                 tgt: (.[ $tgt ]/1024/1024/1024 | round)}
              | if .tgt >= .src then
                  "Target disk is big enough: \($tgt) (\(.tgt) GB) >= \($src) (\(.src) GB)"
                else
                  error("FAIL: \($tgt) (\(.tgt) GB) < \($src) (\(.src) GB)")
                end
            ' 2>&1); then
            echo >&2 "ERROR: $install_target too small: $out"
            exit 1
          else
            echo "$out"
          fi

          echo "Copying source disk \"$install_source\" to target disk \"$install_target\"."
          ddrescue -f -v "$install_source" "$install_target"
          printf "fix\n" | parted ---pretend-input-tty "$install_target" print
          sync

          echo "Done. Please remove the installation medium and reboot."
          echo 1 > /run/installer_done

          echo "Press any key to continue"
          read -r confirm

          systemctl reboot
        '';
      };
    };
  };
}
