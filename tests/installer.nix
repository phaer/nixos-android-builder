{ modules, lib, ... }:
{
  name = "nixos-android-builder-installer-test";
  nodes.machine =
    { config, ... }:
    {
      imports = modules;
      config = {
        # Decrease resource usage for VM tests a bit as long as we are not actually
        # building android as part of the test suite.
        systemd.repart.partitions = lib.optionalAttrs (config.nixosAndroidBuilder.ephemeralVarLib) {
          "30-var-lib".SizeMinBytes = lib.mkVMOverride "10G";
        };
        testing.initrdBackdoor = true;
        virtualisation = lib.mkVMOverride {
          diskSize = 30 * 1024;
          memorySize = 8 * 1024;
          cores = 8;
          emptyDiskImages = [
            # Empty disk image as installation target
            config.virtualisation.diskSize
          ];
        };
      };
    };

  testScript =
    { nodes, ... }:
    ''
      import os
      import subprocess
      env = os.environ.copy()

      # Use world-readable, throw-away test keys to sign the writable image
      # copy used for this test run.
      env["keystore"] = "${nodes.machine.system.build.secureBootKeysForTests}"
      # Prepare the writable disk image
      subprocess.run([
        "${lib.getExe nodes.machine.system.build.prepareWritableDisk}"
      ], env=env, cwd=machine.state_dir, check=True)
      disk_image = "${nodes.machine.virtualisation.diskImage}"

      serial_stdout_on()
      machine.start()

      machine.wait_for_console_text("enrolled. Rebooting...")
      machine.wait_for_shutdown()

      machine.start()
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
      _status, stdout = machine.execute("bootctl status")
      t.assertIn(
        "Secure Boot: enabled (user)", stdout,
        "Secure Boot is NOT active")
      machine.shutdown()
    '';
}
