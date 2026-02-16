---
title: NixOS Android Builder User Guide
---

\pagebreak

This document describes the steps needed to build a disk image for NixOS Android Builder, boot it on a target machine and build Android Open Source Project with it.

At the end, it provides an overview on customization options as well as guidance on keeping the project up to date with upstream sources.

A more detailed architecture and technical description is available in [docs.pdf](docs.pdf).

# Requirements

  * A **local machine** to build the image. Any machine with [nix](https://nixos.org/nix) installed, that can build for `x86_64-linux` targets should suffice. It needs...
    - ~4GB of memory for nix evaluation
    - ~30GB of disk space for dependencies as well as the built images

  * A **USB mass storage** device, such as an USB stick, to transfer the built image to the target machine. It needs  about 3GB of storage to boot.

  * A **target machine** on which to build Android on. It needs:
    - ~64G of memory
    - ~250G of free disk space
    - EFI boot with secure boot in setup mode

  * A **git checkout** of this repository, containing nix expressions and helper scripts to build the image.
    Commands in this document assume to be run from the repository’s top-level directory, unless explicitly stated otherwise.

\pagebreak

#  Preparations on your local machine

## Create Secure Boot Keys

We ship a small helper script, `create-signing-keys`, in our repo that generates a key pair to sign our Unified Kernel Image (`UKI`) with for secure boot.
The script is intended to be run from the repository’s top-level directory and will write keys, certificates, etc. to a `keys/` directory relative to you current working directory.

Those keys are required for Secure Boot signing and enrollment of target machines.
They need to be stored **secure** and **safely**, and **must not** be committed to the repository plain text.

How to handle that is currently left to the user to decide.
Various 3rd-party tools such as [SOPS](https://github.com/getsops/sops/) can be used
for this purpose.

Let’s start by running the following command in a local git checkout of this repository:

```shell-session
$ nix run .#create-signing-keys
```

``` text
>>> Generating UUID
56521b4e-c625-4792-9718-07196c355f66

>>> Generating PK
[...]
>>> Generating KEK
[...]
>>> Generating DB
[...]

total 27
drwxr-xr-x  2 user users   19 Sep 19 13:22 .
drwxr-xr-x 10 user users   20 Sep 19 13:22 ..
-rw-------  1 user users 3374 Sep 19 13:22 db.auth
-rw-r--r--  1 user users 1317 Sep 19 13:22 db.cer
-rw-r--r--  1 user users 1838 Sep 19 13:22 db.crt
-rw-r--r--  1 user users 1361 Sep 19 13:22 db.esl
-rw-------  1 user users 3268 Sep 19 13:22 db.key
-rw-r--r--  1 user users   37 Sep 19 13:22 guid.txt
-rw-------  1 user users 3374 Sep 19 13:22 KEK.auth
-rw-r--r--  1 user users 1317 Sep 19 13:22 KEK.cer
-rw-r--r--  1 user users 1838 Sep 19 13:22 KEK.crt
-rw-r--r--  1 user users 1361 Sep 19 13:22 KEK.esl
-rw-------  1 user users 3272 Sep 19 13:22 KEK.key
-rw-------  1 user users 3374 Sep 19 13:22 PK.auth
-rw-r--r--  1 user users 1317 Sep 19 13:22 PK.cer
-rw-r--r--  1 user users 1838 Sep 19 13:22 PK.crt
-rw-r--r--  1 user users 1361 Sep 19 13:22 PK.esl
-rw-------  1 user users 3272 Sep 19 13:22 PK.key
-rw-------  1 user users 2013 Sep 19 13:22 rm_PK.auth
```

The files listed at the end of the output are the generated keys, certificates, etc in `keys`.
Our signing script, `configure-disk-image sign` will pick them up a few steps further down.

But first...

## Build an Image

Let’s build a ready-to-boot disk image from the nix expressions in this repository.

The following command will automatically download dependencies from the binary cache at [cache.nixos.org](https://cache.nixos.org) and build those not already cached.
Depending on your internet uplink and the speed of your local machine, the first run may take a long time, but subsequent runs will be much faster due to local caching of artifacts.

*Note*: A 3rd-party tool such as [nix-output-monitor](https://github.com/maralorn/nix-output-monitor) can help to gain a better overview of what’s currently being downloaded
or built.
`nix shell nixpkgs#nom` starts a shell with it, where you can just replace `nix build` with `nom build` below.

```shell-session
$ nix build --print-build-logs .#image
```

``` text
[...]
android-builder> Running phase: installPhase
android-builder> renamed 'repart-output.json' -> 'repart-output_orig.json'
android-builder> removed 'repart-output_orig.json'
android-builder> copied 'repart-output.json' -> '/nix/store/[hash]-android-builder-25.11pre-git/repart-output.json'
android-builder> removed 'repart-output.json'
android-builder> copied 'android-builder_25.11pre-git.raw' -> '/nix/store/[hash]-android-builder-25.11pre-git/android-builder_25.11pre-git.raw'
android-builder> removed 'android-builder_25.11pre-git.raw'
```

When `nix` finishes building the image, it creates a symlink - `result` - that points to a `/nix/store` path containing a raw disk image.

That image already contains a full partition table and our NixOS closure including all tools to build Android. It’s almost ready to boot,
but not yet signed for secure boot. We are going to fix that in the next step!

We can see the full path as well as the size of the generated disk image by running i.e.:

```shell-session
$ du --human-readable --apparent-size "$(realpath result/*.raw)"
```

``` text
2.7G    /nix/store/[hash]-android-builder-25.11pre-git/android-builder_25.11pre-git.raw
```

(Your disk image’s size may be slightly different than this example)

## Sign the Image

With our disk image built, we still need to sign it for secure boot, as it still contains an unsigned `UKI` on its EFI System Partition (`ESP`).

`configure-disk-image sign` signs that `UKI` with the keys generated earlier and copies secure boot update bundles into the image so that the firmware can enroll them automatically.

`configure-disk-image sign` deliberately runs outside the nix sandbox in order to be able to access our keys in `keys/` without copying them to the world-readable `/nix/store`.

So we start by copying the image out of the nix store to our current working directory, before signing the `UKI` and copying secure boot update bundles.

To sign your image, run:

```shell-session
$ install -m 600 result/android-builder_25.11pre-git.raw .
$ nix run .#configure-disk-image -- sign --keystore ./keys  --device android-builder_25.11pre-git.raw
```

``` text
Extracting payload UKI...
Signing payload UKI with Secure Boot key...
Writing signed payload UKI back...
✓ Payload UKI signed successfully
Copying keystore files for auto-enrollment...
✓ Keystore files copied to ESP
```

After this step, `android-builder_25.11pre-git.raw` in the repository’s top-level directory is ready to be flashed to a block device in the next step!

## Flash the Image

With our image both built and signed, we are now ready to flash it to a block device, such as a USB stick or external hard drive.

Attach the block device to your local machine and make sure you find its *device path*, e.g. via `lsblk`. We will use `/dev/sdX` as the block
device, `android-builder_25.11pre-git.raw` as our image name in this example. While any tool to write a disk image to a block device could do
the job, we simply use `dd` here and ensure that the kernel’s page cache is flushed by waiting for `sync` to finish before detaching the block
device from the local machine:

```shell-session
$ sudo dd \
  bs=1M status=progress \
  if=android-builder_25.11pre-git.raw \
  of=/dev/sdX
$ sudo sync
```

Replace `/dev/sdX` with the path to your removable device (e.g. `/dev/disk/by-id/...`).

After the `sync` is finished, you can safely move the USB stick or external hard drive to your target machine.

Be sure to enable secure boot setup mode before booting the target machine from the block device for the first time.
This is needed to automatically enroll our keys on first boot of the machine.

The enrolled keys stay valid until either the target machines firmware is reset or the keys are rotated.
So you do **not** need to put secure boot in setup mode again if i.e. an earlier version of the image already enrolled the same keys.

\pagebreak

#  On the Target Machine

After booting, you will be dropped into a NixOS environment with an interactive shell that contains the Android build tools by default.

## Fetch Android
The `fetch-android` script clones the latest AOSP repository into the builder’s workspace and checks out the default branch.
Run it from the shell:

```shell-session
$ fetch-android
```

```text
Fetching android:
  repo.branch      = android-latest-release
  repo.manifestUrl = https://android.googlesource.com/platform/manifest

Downloading Repo source from https://gerrit.googlesource.com/git-repo
remote: Sending approximately 12.31 MiB ...
remote: Counting objects: 271, done
remote: Total 9417 (delta 4518), reused 9417 (delta 4518)
repo: Updating release signing keys to keyset ver 2.3
Updating files: 100% (2/2), done.

Your identity is: CI User <ci@example.com>
If you want to change this, please re-run 'repo init' with --config-name

repo has been initialized in /var/lib/build/source
Syncing: 100% (987/987), done in 35m53.176s
repo sync has finished successfully.
Syncing: 100% (987/987), done in 1m53.939s
repo sync has finished successfully.
```

The downloaded source ends up in `/var/lib/build/source` by default.
The repository and branch, the git identity as well the as the source directory can be customized, both at run-time and at build-time.

If multiple branches are configured via `nixosAndroidBuilder.build.branches`, a `select-branch` script is available that presents a dialog menu on boot (with a 30-second timeout).
The selected branch is saved to `/tmp/selected-branch` and automatically picked up by `fetch-android`.
If only one branch is configured, it is selected automatically without prompting.

See below for [build-time customization](#customization), or `fetch-android --help` for available run-time flags:

``` bash
$ fetch-android --help
```

``` text
Usage: /run/current-system/sw/bin/fetch-android [options] [-- ...repo sync args...]

Options:
  --user-email=EMAIL        Git user.email (default: ci@example.com)
  --user-name=NAME          Git user.name (default: CI User)
  --repo-branch=BRANCH      Repo branch to init (default: android-latest-release, or /tmp/selected-branch if present)
  --repo-manifest-url=URL   Repo manifest URL (default: https://android.googlesource.com/platform/manifest)
  --source-dir=DIR          Source directory (default: /var/lib/build/source)
  -h, --help                Show this help message
```

Lower-level tools such as `repo`, `git`, `gpg`, etc. are available in the shell as well in case `fetch-android` does not fit your needs.

\pagebreak

## Build Android
Once the source is available, build your target product with `build-android`.
It will automatically source the build environment and call the appropriate Android make command.

```shell-session
$ build-android
```

``` text
Building android:
  lunch.target = aosp_cf_x86_64_only_phone-aosp_current-eng
  make.args    =


============================================
PLATFORM_VERSION_CODENAME=REL
PLATFORM_VERSION=16
TARGET_PRODUCT=aosp_cf_x86_64_only_phone
TARGET_BUILD_VARIANT=eng
TARGET_ARCH=x86_64
TARGET_ARCH_VARIANT=silvermont
HOST_OS=linux
HOST_OS_EXTRA=Linux-6.12.44-x86_64-NixOS-25.11-(Xantusia)
HOST_CROSS_OS=windows
BUILD_ID=BP2A.250605.031.A2
OUT_DIR=out
SOONG_ONLY=false
============================================
[...]
[ 38% 5/13 20s remaining] cp if changed out/soong/.intermediates/build/release/build_config /build_flag_system_ext/android_common/build_flags.json

#### build completed successfully (12 seconds) ####
```
(Example output is from a run with all artifacts already built. First run will be much more verbose).

The product and variant to build can be customized, both at run-time and at build-time.
See below for [build-time customization](#customization), or `build-android --help` for available run-time flags:

``` bash
$ build-android --help
```

``` text
Usage: /run/current-system/sw/bin/build-android [options] [-- ...m args...]

Options:
  --source-dir=DIR      Source directory (default: /var/lib/build/source)
  --lunch-target=VALUE  Lunch target (default: aosp_cf_x86_64_only_phone-aosp_current-eng)
  -h, --help            Show this help message
```

Lower-level tools such as `lunch`, `m`, `ninja`, etc. are available in the shell after loading Androids `envsetup.sh`:

```shell-session
$ cd /var/lib/build/source
$ source build/envsetup.sh
```

Please refer to [upstream documentation](https://source.android.com/docs/setup/build/building) for details about using them.

\pagebreak

## SBOM Generation

`android-sbom` is a lightweight wrapper around `build-android` to generate Software Bills Of Materials (`SBOMs`) using [upstreams SBOM facilities](https://source.android.com/docs/setup/create/create-sbom).

The resulting `SBOM` can be found in `/var/lib/build/source/out/soong/sbom`.

```shell-session
$ android-sbom
```

``` text
Building android:
  lunch.target = aosp_cf_x86_64_only_phone-aosp_current-eng
  make.args    = sbom


============================================
PLATFORM_VERSION_CODENAME=REL
PLATFORM_VERSION=16
TARGET_PRODUCT=aosp_cf_x86_64_only_phone
TARGET_BUILD_VARIANT=eng
TARGET_ARCH=x86_64
TARGET_ARCH_VARIANT=silvermont
HOST_OS=linux
HOST_OS_EXTRA=Linux-6.12.44-x86_64-NixOS-25.11-(Xantusia)
HOST_CROSS_OS=windows
BUILD_ID=BP2A.250605.031.A2
OUT_DIR=out
SOONG_ONLY=false
============================================
[...]
[ 50% 5/10 1m22s remaining] cp if changed out/soong/.intermediates/build/release/build_config /build_flag_product/android_common/build_flags.json

#### build completed successfully (13 seconds) ####
```

(Example output is from a run with all artifacts already built. First run will be much more verbose).

## Save Build Outputs

All build outputs, logs and images can be found in `/var/lib/build/source/out` once the build has finished.
Images in particular are in `out/target/product`, logs in `error.log` and `verbose.log.gz`.

Since the outputs are still stored on the ephemeral `/var/lib/build` partition at the moment, they will effectively be deleted when the target machine shuts down for any reason.
To keep them available between boots, users may set `nixosAndroidBuilder.artifactStorage.enable = true` in `configuration.nix`. During boot, the user will be prompted to select a second disk for persistent artifact storage (mounted at `/var/lib/artifacts`). The target disk can also be pre-configured with `configure-disk-image set-storage`:

```shell-session
$ nix run .#configure-disk-image -- set-storage --target /dev/sdb --device android-builder_25.11pre-git.raw
```

Once artifact storage is enabled, the `copy-android-outputs` script copies build outputs matching the patterns configured in `nixosAndroidBuilder.artifactStorage.contents` from `/var/lib/build/source/out` to `/var/lib/artifacts`, organized by timestamp.

Copying them to a remote persistent storage medium is left to the user at this time.

## Reset to Initial State

To start a fresh build, simply reboot.

Shutting down the machine, even sudden power loss, will flush the disk encryption key from RAM and render all previous build artifacts - except those explicitly copied to `/var/lib/artifacts` - inaccessible.
Upon reboot, the `/var/lib/build` partition will be re-formatted and re-encrypted.

To reboot, use your machine’s physical power buttons or run the following in a shell:

```shell-session
$ systemctl reboot
```

\pagebreak

#  Updates

All dependencies besides Android sources are coming from `nixpkgs`. So just updating the pinned `nixpkgs` revision in our flake, updates all software packages used to build the image.

To update all flake’s inputs, run:

```shell-session
$ nix flake update
```

After updating, (re-)builds of the image will use the latest packages from the tracked `nixpkgs` branch - currently `nixos-25.11`.

To catch possible regression bugs early, we do recommend to run at least the `integration` test as described in [Automated Tests](#automated-tests) below.

# Disk Installer {#disk-installer}

NixOS Android builder image includes an optional disk installer image that can be used to flash the image to a USB device on your local machine before booting from that device on the target machine.

The installer is a disk image that contains a minimal `ESP` partition plus a second partition, `payload` that contains the actual NixOS Android builder image. Upon boot, the `payload` will be flashed to a local disk. Either pre-configured or selected interactively by the user.

To build an installer image & copy it to your current working directory, run:

``` shell-session
$ nix build -L .#installer-image
$ install -m 600 result/disk-installer.raw .
```

To sign both the installer & its included payload for Secure Boot, run:

``` shell-session
$ nix run .#configure-disk-image -- sign --keystore ./keys  --device disk-installer.raw
Extracting installer UKI...
Signing installer UKI with Secure Boot key...
Writing signed installer UKI back...
✓ Installer UKI signed successfully
Extracting payload UKI...
Signing payload UKI with Secure Boot key...
Writing signed payload UKI back...
✓ Payload UKI signed successfully
Copying keystore files for auto-enrollment...
✓ Keystore files copied to ESP
```

The `sign` sub-command accepts additional flags to control what gets signed:

- `--installer` signs only the installer UKI (not the payload).
- `--payload` signs only the payload UKI (not the installer).
- `--no-auto-enroll` skips copying keystore files (`PK.auth`, `KEK.auth`, `db.auth`) to the ESP for Secure Boot auto-enrollment.

If neither `--installer` nor `--payload` is given, both are signed (when applicable).

To configure an installer to install the payload to `/dev/sda` on first boot:

```shell-session
$  nix run .#configure-disk-image -- set-target --target /dev/vda --device disk-installer.raw
✓ Configured installer image for automatic installation
  Will install to: /dev/vda
```

`device` can be either a disk image, or a block device if the image has already been flashed.
`target` can either be `select` to let the user select a disk interactively, or a device path on the target machine to install to that device without user input.

```shell-session
$ nix run .#configure-disk-image -- set-target --target select --device disk-installer.raw
✓ Configured installer image for interactive installation
  User will select target disk during boot
```

There's also a `status` sub-command to check the current configuration and Secure Boot status of a given device or image:

``` shell-session
nix run .#configure-disk-image -- status --keystore ./keys --device disk-installer.raw
Image type: Installer with nested payload

Installation target:
  Interactive menu (user will select target)

Storage target:
  Interactive menu (user will select artifact storage)

Installer Secure Boot status:
  ✓ Signed and verified

Payload Secure Boot status:
  ✓ Signed and verified
```


# Automated Tests {#automated-tests}

The repository ships a NixOS VM test that boots a built image and checks the build environment, secure‑boot enrollment, and dm‑verity status.

To run the tests in a virtual machine on your local machine:

```shell-session
$ nix build -L .#checks.x86_64-linux.integration
```

``` text
Machine state will be reset. To keep it, pass --keep-vm-state
[...]
Copying /nix/store/[hash]-android-builder-25.11test/android-builder_25.11test.raw to android-builder_25.11test.raw
Resizing android-builder_25.11test.raw to 30720M
Image resized.
Signing UKI in android-builder_25.11test.raw
using keystore /nix/store/[hash]-test-keys.
Searching ESP partition offset in android-builder_25.11test.raw
Copying EFI/BOOT/BOOTX64.EFI from the image to /build/tmp.bHZYjbI7BGefi/EFI/BOOT/BOOTX64.EFI
Signing /build/tmp.bHZYjbI7BGefi/EFI/BOOT/BOOTX64.EFI
Signing Unsigned original image
Copying /build/tmp.bHZYjbI7BGefi/EFI/BOOT/BOOTX64.EFI back to the image, into EFI/BOOT/BOOTX64.EFI
Copying certificates from /nix/store/[hash]-test-keys to the image, into EFI/KEYS
Done. You can now flash the signed image:
android-builder_25.11test.raw
android-builder: starting vm
android-builder: QEMU running (pid 37)
android-builder: waiting for unit default.target
android-builder: waiting for the VM to finish booting
[...]
android-builder: (finished: waiting for the VM to finish booting, in 22.43 seconds)
[...]
android-builder: (finished: waiting for unit default.target, in 23.48 seconds)
subtest: secure boot works
android-builder: must succeed: bootctl status
[...]
(finished: subtest: secure boot works, in 0.07 seconds)
subtest: dm-verity works
android-builder: must succeed: veritysetup status usr
android-builder: (finished: must succeed: veritysetup status usr, in 0.04 seconds)
(finished: subtest: dm-verity works, in 0.04 seconds)
subtest: Checking FHS Environment
subtest: /usr/bin/env can be executed
android-builder: must succeed: /usr/bin/env --version
android-builder: (finished: must succeed: /usr/bin/env --version, in 0.02 seconds)
(finished: subtest: /usr/bin/env can be executed, in 0.02 seconds)
subtest: Executables in /bin can be run
android-builder: must succeed: /bin/diff -v
android-builder: (finished: must succeed: /bin/diff -v, in 0.01 seconds)
(finished: subtest: Executables in /bin can be run, in 0.01 seconds)
subtest: /bin/bash sets default $PATH and is a regular file with the correct linker
android-builder: must succeed: env -i /bin/bash -c 'echo $PATH'
android-builder: (finished: must succeed: env -i /bin/bash -c 'echo $PATH', in 0.01 seconds)
android-builder: must succeed: file /bin/bash
android-builder: (finished: must succeed: file /bin/bash, in 0.03 seconds)
(finished: subtest: /bin/bash sets default $PATH and is a regular file with the correct linker, in 0.04 seconds)
subtest: dynamic linkers exist as regular files in /lib(64) and search /lib
android-builder: must succeed: file /lib/ld-linux-x86-64.so.2
android-builder: (finished: must succeed: file /lib/ld-linux-x86-64.so.2, in 0.01 seconds)
android-builder: must succeed: file /lib64/ld-linux-x86-64.so.2
android-builder: (finished: must succeed: file /lib64/ld-linux-x86-64.so.2, in 0.01 seconds)
android-builder: must succeed: /lib/ld-linux-x86-64.so.2 --help
android-builder: (finished: must succeed: /lib/ld-linux-x86-64.so.2 --help, in 0.00 seconds)
(finished: subtest: dynamic linkers exist as regular files in /lib(64) and search /lib, in 0.03 seconds)
(finished: subtest: Checking FHS Environment, in 0.09 seconds)
android-builder: waiting for the VM to power off
[...]
test script finished in 30.40s
cleanup
kill vlan (pid 7)
(finished: cleanup, in 0.00 seconds)
```

Note that the test are only run again if inputs did change since the last run.

There's additional VM tests in the repository cover the the disk installer, see:

``` shell-session
$ nix build -L .#checks.x86_64-linux.installer .#checks.x86_64-linux.installerInteractive

```

# Usage in a Virtual Machine {#virtual-machine}

It is possible to test the whole setup in a [qemu](http://qemu.org/) virtual machine using Nix (currently only tested from `x86_64-linux`):

```shell-session
nix run .#run-vm
```

This will:

1. Create a writable copy of the read-only disk image (e.g. `android-builder_25.11pre-git.raw`) in the current directory.
2. Sign the UKI with a pair of auto-generated test keys (stored in the nix store, so they persist across runs).
3. Pre-configure artifact storage to use `/dev/vdb` (a second virtual disk is created automatically when `nixosAndroidBuilder.artifactStorage.enable` is set).
4. Start a QEMU VM with Secure Boot, a TPM, and a graphical window.

If the writable disk image already exists from a previous run, steps 1–3 are skipped and the existing image is reused. Delete the `.raw` file to force a fresh image.

Use `systemctl poweroff` from within the VM, or close the QEMU window, to stop it.

There is also an `installer-vm` package (`nix run .#installer-vm`) for testing the disk installer workflow in a VM.

# Troubleshooting {#troubleshooting}

## Secure Boot Issues

**Problem: "Secure Boot is disabled" error on boot**

The system requires Secure Boot to be active. Enter your firmware setup (usually F2, F12, or Del during POST) and:

1. Navigate to Security → Secure Boot
2. Enable Secure Boot
3. Save and reboot

**Problem: "Secure Boot setup mode" – keys won't enroll**

Ensure the firmware is in Setup Mode, not User Mode with existing keys:

1. Enter firmware setup
2. Navigate to Security → Secure Boot → Key Management
3. Select "Clear All Secure Boot Keys" or "Reset to Setup Mode"
4. Save and reboot

**Problem: Boot fails after key enrollment**

The image may have been signed with different keys than those enrolled. Re-sign the image with the correct keystore:

```shell-session
$ nix run .#configure-disk-image -- status --keystore ./keys --device <image>
```

Verify the signature status shows "Signed and verified."

## Boot Issues

**Problem: "dm-verity: Hash verification failed"**

The store partition has been corrupted or tampered with. The image must be rebuilt and reflashed.


**Problem: System boots but drops to emergency shell**

Check the journal for errors:

```shell-session
$ journalctl -e
```

Common causes:

- Disk too small (needs 250GB minimum)
- Hardware compatibility issues

## Android Build Issues

**Problem: `fetch-android` fails with network errors**

Ensure the target machine has network access to `android.googlesource.com`. For air-gapped environments, configure a local mirror:

```shell-session
$ fetch-android --repo-manifest-url=https://your-internal-mirror/platform/manifest
```

**Problem: `build-android` fails with "command not found"**

The FHS environment may not be properly initialized. Verify the bind mounts:

```shell-session
$ mount | grep -E '/bin|/lib'
$ ls -la /bin/bash /lib/ld-linux-x86-64.so.2
```

**Problem: Build outputs disappeared after reboot**

This is expected behavior – the `/var/lib/build` partition is ephemeral by design. To persist outputs, enable artifact storage: set `nixosAndroidBuilder.artifactStorage.enable = true` in `configuration.nix`.


## VM Testing Issues

**Problem: `nix run .#run-vm` fails with "KVM not available"**

Hardware virtualization must be enabled. Check and enable in firmware:

```shell-session
$ lsmod | grep kvm  # Should show kvm_intel or kvm_amd
```

If missing, enable VT-x/AMD-V in BIOS/UEFI settings.

**Problem: Can't exit the VM**

Use `Ctrl-A x` to terminate QEMU, or from within the VM:

```shell-session
$ systemctl poweroff
```

\pagebreak

# Customization {#customization}

The following NixOS Options are available to customize features & behaviour of NixOS Android Builder at build-time.
Some, e.g. those in the `nixosAndroidBuilder.build` namespace, also have equivalent flags to use at run-time where an interactive shell is available.

Settings can be set in `configuration.nix`.

{{nixos-options}}
