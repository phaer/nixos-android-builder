# Adapted From: nixpkgs/nixos/tests/appliance-repart-image.nix
{ customModules, ... }:
let
  imageId = "nixos-appliance";
  imageVersion = "0.1";
in {
  name = "android-builder-image";
  nodes.machine = { ... }: {
    imports = customModules;
    config = {
      system.name = imageId;
      system.nixos.version = imageVersion;
    };
  };

  testScript =
    { nodes, ... }:
    ''
      import os
      import subprocess
      import tempfile

      tmp_disk_image = tempfile.NamedTemporaryFile()

      subprocess.run([
        "${nodes.machine.virtualisation.qemu.package}/bin/qemu-img",
        "create",
        "-f",
        "qcow2",
        "-b",
        "${nodes.machine.system.build.image}/${nodes.machine.image.fileName}",
        "-F",
        "raw",
        tmp_disk_image.name,
      ])

      # Set NIX_DISK_IMAGE so that the qemu script finds the right disk image.
      os.environ['NIX_DISK_IMAGE'] = tmp_disk_image.name

      os_release = machine.succeed("cat /etc/os-release")
      assert 'IMAGE_ID="${imageId}"' in os_release
      assert 'IMAGE_VERSION="${imageVersion}"' in os_release

      bootctl_status = machine.succeed("bootctl status")
      assert "Boot Loader Specification Type #2 (.efi)" in bootctl_status
    '';
}
