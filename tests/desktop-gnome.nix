{
  desktopModules,
  customPackages,
  lib,
  ...
}:
{
  name = "desktop-gnome-test";

  # U2F authentication (YubiKey) is not tested here — see desktop.nix
  # for rationale (pam_u2f needs a real USB HID device).

  nodes.machine =
    { pkgs, ... }:
    {
      imports = desktopModules;
      config = {
        _module.args = { inherit customPackages; };

        desktop.gnome = true;

        # Clear YubiKey groups so yubikey-auth.nix leaves PAM defaults
        # intact and falls back to password auth. pam_u2f cannot be
        # tested in QEMU — it requires a real USB HID FIDO2 device.
        nixosAndroidBuilder.yubikeys.groupA = lib.mkForce [ ];
        nixosAndroidBuilder.yubikeys.groupB = lib.mkForce [ ];

        # Set a known password for the test user so we can log in
        # through tuigreet without U2F.
        users.users.user.hashedPassword = "$6$IQa3TAd7zSqu0PUX$YB0xu1nCT5O/vL.309PMiDO4gmPmyGOaRLzAdmSWYL3VmSmeBPtIEZg1TW.NkXrGO9Cc8Gxxklwqmif5.9qc.1"; # "test"

        virtualisation = lib.mkVMOverride {
          diskSize = 30 * 1024;
          memorySize = 8 * 1024;
          cores = 8;
          writableStore = false;
          mountHostNixStore = false;
        };
      };
    };

  testScript =
    { nodes, ... }:
    ''
      import os
      import os.path
      import subprocess
      env = os.environ.copy()

      # Prepare the writable disk image (signing, resizing, etc.)
      subprocess.run([
        "${lib.getExe nodes.machine.system.build.prepareWritableDisk}"
      ], env=env, cwd=machine.state_dir, check=True)

      serial_stdout_on()
      machine.start(allow_reboot=True)
      machine.wait_for_unit("default.target")

      with subtest("greetd is running"):
        machine.wait_for_unit("greetd.service")

      with subtest("login starts GNOME session"):
        # tuigreet shows the greeting; type credentials.
        machine.wait_until_tty_matches("1", "NixOS Desktop")
        machine.send_chars("user\n")
        machine.sleep(1)
        machine.send_chars("test\n")

        # Wait for the user's graphical session to activate.
        # Use wait_until_succeeds because the user's systemd instance
        # may not be reachable immediately after login.
        machine.wait_until_succeeds(
          "systemctl --user --machine=user@ is-active graphical-session.target",
          timeout=120
        )

      with subtest("wayland compositor is running"):
        machine.wait_for_file("/run/user/1000/wayland-0")

      machine.shutdown()
    '';
}
