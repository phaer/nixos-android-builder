{
  lib,
  config,
  pkgs,
  ...
}:
let
  disk-installer = pkgs.callPackage ../packages/disk-installer { };
in
{
  boot.initrd.systemd = {
    contents."/etc/terminfo".source = "${pkgs.ncurses}/share/terminfo";

    initrdBin = [
      pkgs.parted
      disk-installer.run
    ];
    extraBin = {
      lsblk = "${pkgs.util-linux}/bin/lsblk";
      tee = "${pkgs.coreutils}/bin/tee";
      jq = "${pkgs.jq}/bin/jq";
      ddrescue = "${pkgs.ddrescue}/bin/ddrescue";
      dialog = "${pkgs.dialog}/bin/dialog";
      systemd-cat = "${pkgs.systemdMinimal}/bin/systemd-cat";
      chvt = "${pkgs.kbd}/bin/chvt";
    };

    services = {
      find-boot-partition = {
        description = "Find /boot partition of the installer";

        before = [
          "boot.mount"

          "initrd-root-fs.target"
          "systemd-repart.service"
          "generate-disk-key.service"
          "sysroot.mount"
          "sysusr-usr.mount"
          "systemd-veritysetup@usr.service"
        ];
        wantedBy = [ "initrd-fs.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "no";
        };
        unitConfig = {
          DefaultDependencies = false;
        };

        onFailure = [ "fatal-error.target" ];
        script = ''
          boot=""
          temp_dir=$(mktemp -d --suffix "boot")
          cleanup() {
              umount $temp_dir && rm -rf "$temp_dir" || true
          }
          trap "cleanup" EXIT

          sleep 2
          udevadm settle -t 10
          for partition in $(lsblk -o NAME,FSTYPE --list --json | jq -r '.blockdevices[] | select(.fstype=="vfat") | "/dev/\(.name)"'); do
            mount -o ro "$partition" $temp_dir
            if [ -e $temp_dir/install_target ]; then
               boot="$partition"
               break
            fi
          done
          if [ -z "$boot" ]; then
            echo "Couldn't find installers /boot partition, skipping installer" >&2
            exit 0
          else
            echo "Found installers /boot partition in $partition, remounting"
            mkdir -p /run/systemd/system/boot.mount.d
            cat > /run/systemd/system/boot.mount.d/override.conf <<EOF
          [Mount]
          What=$boot
          EOF
            systemctl daemon-reload
          fi
        '';

      };

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
          "systemd-veritysetup@usr.service"
        ];

        wants = [ "initrd-root-device.target" ];
        wantedBy = [ "initrd-root-fs.target" ];

        unitConfig = {
          DefaultDependencies = false;
          ConditionPathExists = "/boot/install_target";
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

        onFailure = [ "fatal-error.target" ];
        script = lib.getExe disk-installer.run;
      };
    };
  };
}
