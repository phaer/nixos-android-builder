{
  desktopModules,
  customPackages,
  lib,
  ...
}:
{
  name = "desktop-integration-test";
  nodes.machine =
    { ... }:
    {
      imports = desktopModules;
      config = {
        _module.args = { inherit customPackages; };
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

      # Prepare the writable disk image
      subprocess.run([
        "${lib.getExe nodes.machine.system.build.prepareWritableDisk}"
      ], env=env, cwd=machine.state_dir, check=True)

      serial_stdout_on()
      machine.start(allow_reboot=True)
      machine.wait_for_unit("default.target")

      with subtest("greetd is running"):
        machine.wait_for_unit("greetd.service")

      with subtest("secure boot works"):
        _status, stdout = machine.execute("bootctl status")
        assert "Secure Boot: enabled (user)" in stdout, \
          f"Secure Boot is NOT active: {stdout}"

      with subtest("root is ext4 on disk"):
        output = machine.succeed("mount | grep ' / '")
        assert "ext4" in output, f"root is not ext4: {output}"
        assert "rw" in output, f"root is not writable: {output}"

      with subtest("nix with flakes is available"):
        machine.succeed("nix --version")
        output = machine.succeed("nix show-config 2>&1 | grep experimental-features")
        assert "flakes" in output, f"flakes not enabled: {output}"

      with subtest("git is available"):
        machine.succeed("git --version")

      with subtest("data persists across reboot"):
        machine.succeed("echo 'hello-desktop' > /home/user/sentinel")
        machine.succeed("cat /home/user/sentinel")

        machine.reboot()
        machine.wait_for_unit("default.target")

        output = machine.succeed("cat /home/user/sentinel").strip()
        assert output == "hello-desktop", \
          f"Expected 'hello-desktop', got '{output}'"

      machine.shutdown()
    '';
}
