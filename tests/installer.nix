{
  modules,
  payload,
  lib,
  ...
}:
{
  name = "nixos-android-builder-installer-test";
  nodes.machine = {
    imports = modules ++ [ ../packages/disk-installer/installer-vm.nix ];
    config = {
      testing.initrdBackdoor = true;
      diskInstaller.payload = lib.mkForce payload;
    };
  };

  testScript =
    { nodes, ... }:
    ''
      import os
      import subprocess
      from pathlib import Path

      read_only_image = Path("${nodes.machine.virtualisation.diskImage}")
      writable_image = Path(machine.state_dir) / read_only_image.with_suffix(".qcow2").name
      target_image = Path(machine.state_dir) / "empty0.qcow2"

      args = [
        "qemu-img", "convert", "-f", "raw", "-O", "qcow2", str(read_only_image), str(writable_image)
      ]
      print(args)
      subprocess.run(args, cwd=machine.state_dir)
      os.environ["NIX_DISK_IMAGE"] = str(writable_image)

      serial_stdout_on()
      machine.start()

      machine.wait_for_file("/run/installer_done")
      machine.shutdown()

      subprocess.run([
        "mv", str(target_image), str(writable_image)
      ], cwd=machine.state_dir)
      subprocess.run([
        "ls"
      ], cwd=machine.state_dir)

      machine.start()
      machine.switch_root()
      machine.wait_for_unit("multi-user.target")
      machine.shutdown()
    '';
}
