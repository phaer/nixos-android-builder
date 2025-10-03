{ modules, lib, ... }:
{
  name = "nixos-android-builder-integration-test";
  nodes.machine =
    { ... }:
    {
      imports = modules;
      config = {
        # Decrease resource usage for VM tests a bit as long as we are not actually
        # building android as part of the test suite.
        systemd.repart.partitions."30-var-lib".SizeMinBytes = lib.mkVMOverride "10G";
        virtualisation = lib.mkVMOverride {
          diskSize = 30 * 1024;
          memorySize = 8 * 1024;
          cores = 8;
        };
      };
    };

  testScript =
    { nodes, ... }:
    let
      testFHSEnv = ''
        with subtest("Checking FHS Environment"):
          with subtest("/usr/bin/env can be executed"):
            t.assertIn(
              "env (GNU coreutils)", machine.succeed("/usr/bin/env --version"),
              "/usr/bin/env --version can't be executed"
            )
          with subtest("Executables in /bin can be run"):
             t.assertIn(
              "diff (GNU diffutils)", machine.succeed("/bin/diff -v"),
              "failed to execute /bin/diff -v"
            )
          with subtest("/bin/bash sets default $PATH and is a regular file with the correct linker"):
            t.assertIn(
              "/bin", machine.succeed("env -i /bin/bash -c 'echo $PATH'"),
              "/bin/bash does not have /bin in $PATH if run in an empty environment"
            )

            file_bin_bash = machine.succeed("file /bin/bash")
            t.assertIn(
              "interpreter /lib/ld-linux-x86-64.so.2", file_bin_bash,
              "/bin/bash does not have the right dynamic linker set"
            )
            t.assertNotIn(
              "symbolic link to ", file_bin_bash,
              "/bin/bash should not be a symlink"
            )

          with subtest("dynamic linkers exist as regular files in /lib(64) and search /lib"):
            t.assertNotIn(
              "symbolic link to ", machine.succeed("file /lib/ld-linux-x86-64.so.2"),
              "/lib/ld-linux-x86-64.so.2 should not be a symlink"
            )
            t.assertNotIn(
              "symbolic link to ", machine.succeed("file /lib64/ld-linux-x86-64.so.2"),
              "/lib64/ld-linux-x86-64.so.2 should not be a symlink"
            )

            t.assertIn(
              " /lib (system search path)", machine.succeed("/lib/ld-linux-x86-64.so.2 --help"),
              "search path of /lib/ld-linux-x86-64.so.2 does not contain /lib ")
      '';

      testVerity = ''
        with subtest("dm-verity works"):
          t.assertRegex(
          machine.succeed("veritysetup status usr"),
          r'status:\s+verified')
      '';

      testSecureBoot = ''
        with subtest("secure boot works"):
          t.assertIn(
            "Secure Boot: enabled (user)", machine.succeed("bootctl status"),
            "Secure Boot is NOT active")
      '';
    in
    ''
      import os
      import os.path
      import subprocess
      env = os.environ.copy()

      # Use world-readable, throw-away test keys to sign the writable image
      # copy used for this test run.
      env["keystore"] = "${nodes.machine.system.build.secureBootKeysForTests}"
      # Prepare the writable disk image
      subprocess.run([
        "${lib.getExe nodes.machine.system.build.prepareWritableDisk}"
      ], env=env, cwd=machine.state_dir, check=True)

      serial_stdout_on()
      machine.start(allow_reboot=True)
      machine.wait_for_unit("default.target")
      ${testSecureBoot}
      ${testVerity}
      ${testFHSEnv}
      machine.shutdown()
    '';
}
