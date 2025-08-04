# NixOS Android Builder

This repository contains a Proof-of-Concept Nix flake setup to build NixOS images that boot into memory while keeping state in a persistent `/var/lib` partition. That partition will be expanded and (re-)encrypted with
a ephemeral key on each boot. No state is persisted between boots by default.

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
* EFI Boot

# Usage in a Virtual Machine

It is possible to test the whole setup in a [qemu](http://qemu.org/) virtual machine using Nix (currently only tested from `x86_64-linux`), after preparing a writable disk image, `android-builder.qcow2` in the current working directory.

```shell-session
nix run .#create-vm-disk
nix run .#run-vm
```

Will start a head-less VM with a console in the current terminal. Use `Ctrl-A x` or `systemctl poweroff` to stop the VM.

The command above will create a `qcow2` disk image for the persistent storage in the current directory, if one does not exist already. That disk image can be deleted as needed to do a "factory reset" of the builder. It's mostly used as a cache for sources and build artifacts.

# Usage on Bare Metal

To deploy the builder to physical hardware, we can build a disk image:

```shell-session
$ nix build .#image
$ realpath -e result/android-builder_*.raw
/nix/store/1rr1x8q3ak1r34w8jlgmp25kzr45ny6s-android-builder-25.11pre-git/android-builder_25.11pre-git.raw
```

(the hash in your store path will likely be different)

That image can then be copied to a USB stick or hard-drive with e.g. `sudo dd if="$(realpath -e result/android-builder_*.raw)" bs=1M status=progress of=/dev/your-device` or other utils and booted on EFI-enabled x86_64 machines.

# Secure Boot

There are scripts included for secure boot key creation and signing the image. They should be run in the included devshell, after building `.#image` but before flashing it.

```sh
./create-signing-keys.sh
./sign.sh
```

`openssl` is used to generate new secure boot keys. The keys are stored into `./keys` directory.
This process is meant to be done outside of the target hardware, in a centralized way.

Be sure to keep the `*.key` files safe and private! Other generated files are safe to distribute.
Various formats of public keys and certs are generated to be compatible with most UEFIs and use cases.

The signing script copies the public keys from `./keys` into the raw image at `/boot/EFI/keys` where they can be enrolled from -
either by using the included UEFI gui, or by booting the image with secure boot in setup mode and using the included `enroll-secure-boot` script.

```sh
# uses efi-updatevar under the hood
enroll-secure-boot

# reboot to UEFI now to enable secure boot
sudo systemctl reboot --firmware-setup
```
