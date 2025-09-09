# NixOS Android Builder

This repository contains a Proof-of-Concept Nix flake setup to build NixOS images that boot into memory while keeping state in a persistent `/var/lib` partition. That partition will be expanded and (re-)encrypted with
a ephemeral key on each boot. No state is persisted between boots by default.

It's not hardnened by default. To the contrary: It includes a single account `users` that is automatically logged in on `tty1` and `ttyS0` and has password-less sudo permission and a persistent home in `/var/lib/build`.

# Build Environment

Androids build system assumes to be run inside a Linux environment that resembles a conventional Linux File System Hierachy (FHS) with executables in `/bin`, dynamic libraries in `/lib`, and so on.

One might be inclined to do so by linking nix store path to FHS paths with e.g. `pkgs.buildFHSEnv`, an approach that works for simpler build systems. But Androids build system contains sandboxing utils such as nsjail, that run a container that only mounts FHS paths, but not the nix store itself, leading to broken symlinks in `/bin` from the perspective of a process running in such a container.
Tools like envfs and nix-ld run into similar issues with sandboxes, by depending on the  availibility of `/nix/store `in the same mount namespace as your proces runs.

We therefore prepare /lib and /bin directories, containing no symlinks, but regular files for all dependencies needed to build AOSP.
The we run patchelf on those binaries to set both, their run path, as well as their interpreter to conventional FHS paths.
We also add two custom packages:
- A `/bin/bash` (and `/bin/sh`) build that has a default $PATH that includes `/bin`, even with an empty environment. That's the same behavior as conventional Linux Distributions such as Debian have, but different to NixOS defaults.
- A glibc build that differs from NixOS in that uses FHS paths, and therefore searches `/lib` for libraries by default.

`/lib` and `/bin `are currently shipped as a single nix derivation, and bind-mounted to the host file system during boot.

---

Two simple shell scripts are available in the shell for quick testing & demos:

* `fetch-android` sets up git and checks out `android-latest-release` into `/var/lib/build/source` using [repo](https://android.googlesource.com/tools/repo).
* `build-android` demonstrates a trivial build of `aosp_cf_x86_64_only_phone-aosp_current-userdebug`.

No further customization or handling of build artifacts is currently implemented.
Resulting artifacts can be found in-tree in `/var/lib/build/source/out` after the
build has finished.

See [./docs/docs.md](docs.md) for a more detailed description of design considerations, used components and furhter work.

# Requirements

* [Nix](https://nixos.org) with flakes support
* At least 64G of memory to build Android.
* An empty disk with at least 250G for bare metal deployments, or space for an image of the same size for the VM.
* EFI Boot

# Usage in a Virtual Machine

It is possible to test the whole setup in a [qemu](http://qemu.org/) virtual machine using Nix (currently only tested from `x86_64-linux`), in the current working directory.

```shell-session
nix run .#run-vm
```

This will create a writable copy of the read-only disk image, e.g. `android-builder_25.11pre-git.raw` in the local directory and sign ith with a pair of test keys,
before starting a head-less VM with a console in the current terminal. Use `Ctrl-A x` or `systemctl poweroff` to stop the VM.

# Usage on Bare Metal

To deploy the builder to physical hardware, we can build a disk image:

```shell-session
$ nix build .#image
```

This will take a while on first build, but eventually result in read-only disk image in the nix store and link it in `result`, e.g.: `./result/android-builder_25.11pre-git.raw`.

## Secure Boot

To prepare our image for SecureBoot, we first have to copy it to a location where we can write to it, and then run two of our included scripts for key creation and image signing.
Those scripts can be run from the included devshell (`nix develop`) or by using `nix run`, i.e. `nix run .#create-signing-keys`:

```shell-session
# Create SecureBoot keys
create-signing-keys
# Build the image, copy it to our current working directory and make it writable
install -T $(nix build --no-link --print-out-paths .#image)/*.raw android_builder.raw
# Finally, sign the UKI on the images ESP partition
sign-disk-image android_builder.raw
```

`openssl` is used to generate new secure boot keys. The keys are stored into `$PWD/keys` directory.
This process is currently expected to be run from this repo on your workstation, not the target machine.

Be sure to keep the `*.key` files safe and private! Other generated files should be relatively safe to distribute. Various formats of public keys and certs are generated to be compatible with most UEFIs and use cases. The current setup does not over revocation lists nor does it guard against downgrade attacks.

The signing script copies the public keys from `./keys` into the raw image at `/boot/EFI/KEYS`. We check whether the machine has booted in Secure Boot mode and whether it is in setup mode. If it's in setup mode, we enroll the keys in `/boot/EFI/KEYS` automatically and reboot. If Secure Boot is disabled,
an error is displayed and the machine halted.

## Flashing it

The result image can then be copied to a USB stick or hard-drive with e.g. `sudo dd if=android_builder.raw bs=1M status=progress of=/dev/your-device` or other utils and booted on EFI-enabled x86_64 machines.


# Automated Testing

There's a NixOS VM Test that boots the built image in a virtual machine and checks whether the Android build env is in order, and wheter dm-verity and secure boot, including enrollment, work.

```shell-session
nix build -L .#checks.x86_64-linux.integration
```

