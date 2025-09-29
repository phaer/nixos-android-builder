{ modules, lib, ... }:
{
  name = "nixos-android-builder-installer-test";
  nodes.machine =
    { ... }:
    {
      imports = modules;
      config = {
        # Decrease resource usage for VM tests a bit as long as we are not actually
        # building android as part of the test suite.
        systemd.repart.partitions."30-var-lib".SizeMinBytes = lib.mkVMOverride "10G";
        testing.initrdBackdoor = true;
        virtualisation = lib.mkVMOverride {
          diskSize = 30 * 1024;
          memorySize = 8 * 1024;
          cores = 8;
          emptyDiskImages = [
            # Empty disk image as installation target
            (31 * 1024)
          ];
        };
      };
    };

  testScript =
    { nodes, ... }:
    ''
      import os
      import subprocess
      import time
      env = os.environ.copy()

      # Use world-readable, throw-away test keys to sign the writable image
      # copy used for this test run.
      env["keystore"] = "${nodes.machine.system.build.secureBootKeysForTests}"
      # Prepare the writable disk image
      subprocess.run([
        "${lib.getExe nodes.machine.system.build.prepareWritableDisk}"
      ], env=env, cwd=machine.state_dir)
      disk_image = "${nodes.machine.virtualisation.diskImage}"

      serial_stdout_on()
      machine.start(allow_reboot=True)

      # TODO: Secure Boot enrollment needs to reboot the machine
      # once, before the installer gets a chance to run. I wasted
      # too much time, trying to search for "enrolled. Rebooting"
      # with wait_for_console_text() and friends, before succumbing to a long-enough wait
      time.sleep(15)

      machine.wait_for_file("/run/installer_done")
      machine.shutdown()

      subprocess.run([
        "ls", disk_image
      ], env=env, cwd=machine.state_dir)
      subprocess.run([
        "rm", disk_image
      ], env=env, cwd=machine.state_dir)

      subprocess.run([
        "qemu-img", "convert", "-f", "qcow2", "-O", "raw", "empty0.qcow2", disk_image
      ], env=env, cwd=machine.state_dir)
      subprocess.run([
        "rm", "empty0.qcow2"
      ], env=env, cwd=machine.state_dir)


      machine.start()
      machine.switch_root()
      machine.wait_for_unit("multi-user.target")
      t.assertIn(
          "Secure Boot: enabled (user)", machine.succeed("bootctl status"),
          "Secure Boot is NOT active")
      machine.shutdown()
    '';
}
