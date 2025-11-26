{
  installerModules,
  payload,
  lib,
  ...
}:
{
  name = "nixos-android-builder-installer-test";
  nodes.machine = {
    imports = installerModules;
    config = {
      testing.initrdBackdoor = true;
      diskInstaller.payload = lib.mkForce payload;
      nixosAndroidBuilder.configureInstallerForVm = "/dev/vdb";
    };
  };

  testScript =
    { nodes, ... }:
    ''
      import subprocess

      subprocess.run([
        "${lib.getExe nodes.machine.system.build.prepareInstallerDisk}"
      ], cwd=machine.state_dir, check=True)

      serial_stdout_on()
      machine.start()

      machine.wait_for_file("/run/installer_done")
      machine.shutdown()

      subprocess.run([
        "mv", "empty0.qcow2", "${nodes.machine.virtualisation.diskImage}"
      ], cwd=machine.state_dir)
      subprocess.run([
        "ls"
      ], cwd=machine.state_dir)

      machine.start()
      machine.wait_for_unit("multi-user.target")
      machine.shutdown()
    '';
}
