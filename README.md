# NixOS Android Builder

This repository contains a Proof-of-Concept Nix flake setup to build NixOS images that boot from a read-only
disk - such as an USB stick - into memory while formatting a physical disk to persist
build artifacts and other data in `/var/lib` as they might be bigger than available memory.

It's not hardnened by default. To the contrary: It includes a single account `users` that is automatically logged in on `tty1` and `ttyS0` and has password-less sudo permission and a persistent home in `/var/lib/build`.

The users shell includes a command `android-build-env` which starts a shell inside a [bubblewrap](https://github.com/containers/bubblewrap) sandbox, mimicking a conventional [FHS](https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard) layout with required [tooling to build AOSP](https://source.android.com/docs/setup/start) and two scripts:

* `fetch-android` sets up git and checks out `android-latest-release` into `/var/lib/build/source` using [repo](https://android.googlesource.com/tools/repo).
* `build-android` demonstrates a trivial build of `aosp_cf_x86_64_only_phone-aosp_current-userdebug`.

No further customization or handling of build artifacts is currently implemented.
Resulting artifacts can be found in-tree in `/var/lib/build/source/out` after the
build has finished.

# Requirements

* [Nix](https://nixos.org) with flakes support
* At least 64G of memory to build Android.
* An empty disk with at least 250G for bare metal deployments, or space for an image of the same size for the VM.

# Usage in a Virtual Machine

It is possible to test the whole setup in a [qemu](http://qemu.org/) virtual machine using Nix (currently only tested from `x86_64-linux`):

```bash
nix run .#run-vm
```

Will start a head-less VM with a console in the current terminal. Use `Ctrl-A x` or `systemctl poweroff` to stop the VM.

The command above will create a `qcow2` disk image for the persistent storage in the current directory, if one does not exist already. That disk image can be deleted as needed to do a "factory reset" of the builder. It's mostly used as a cache for sources and build artifacts.

# Usage on Bare Metal

To deploy the builder to physical hardware, we can build a disk image with:

```bash
ls $(nix build .#image -L --print-out-paths)
android-builder_25.11pre-git.raw
```

This image can then be copied to a USB stick or hard-drive with `dd` or other utils and booted on EFI-enabled x86_64 machines. It will format an empty disk on first boot.

That disk is `/dev/vdb` by default, and needs to be adapted for bare metal deployments by setting `boot.initrd.systemd.repart.device` to the device path of your target disk.

You may also set `boot.initrd.systemd.repart.empty = "force"` to always ERASE all contents of the disk on each boot to effectively opt out of persistence.
