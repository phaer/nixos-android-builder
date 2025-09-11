---
title: NixOS Android Builder
---

\pagebreak
# Design Principles

With the goal of enabling offline, SLSA‑compliant builds for custom distributions of Android AOSP, we set out to create a minimal Linux system with the following properties:

* **Portable** – Runs on arbitrary `x86_64` hardware with UEFI boot, that provides sufficient disk (>=250 GB) and memory (>=64 GB) to build Android.
* **Offline** – Requires no network connectivity other than to internal source‑code and artifact repositories.
* **Ephemeral** – Each boot of the builder should result in a pristine environment; no trace of build inputs or artifacts should remain after a build.
* **Declarative** – All aspects of the build system are described in Nix expressions, ensuring identical behavior regardless of the build environment or the time of build.
* **Trusted** – All deployed artifacts, such as disk images, are cryptographically signed for tamper prevention and provenance.

We created a modular proof‑of‑concept based on NixOS that fulfills most of these properties, with the remaining limitations and future plans detailed below.

## Limitations and Further Work

* **aarch64 support** could be added if needed. Only `x86_64` with `UEFI` is implemented at the moment.
* **unattended mode** is not yet fully-tested. The current implementation includes an interactive shell and debug tools.
* **artifact uploads**: build artifacts are currently not automatically uploaded anywhere, but stay on the build machine until it is rebooted..
  Integration of a Trusted Platform Module (TPM) could be useful here, to ease authentication to private repositories as well as destinations for artifact upload.
* **measured boot**: while we use Secure Boot with a platform custom key, we do not measure involved components via a TPM yet. Doing so would improve existing Secure Boot measures as well as help with implementing attestation capabilities later on.
* **credential handling** we do not currently implement any measures to handle secrets other than what NixOS ships out of the box.
* **higher-level configuration**: Adapting the build environment to the needs of custom AOSP distributions might need extra work. Depending on the nature of those
  customizations, a good understanding of `nix` might be needed. We will ease those as far as possible, as we learn more about users customization needs.


# Used Technologies

- **[`NixOS`](https://nixos.org)** - the Linux distribution chosen for its declarative module system and flexible boot process.
- **[`nixpkgs`](https://github.com/nixos/nixpkgs)** - the software repository that enables reproducible builds of up‑to‑date open‑source packages.
- **[`qemu`](https://qemu.org)** - used to run virtual machines during interactive, as well as automated testing. Both help to decrease testing & verification cycles during development & customization.
- **[`systemd`](https://systemd.io)** - orchestrates both upstream and custom components while managing credentials and persistent state.
- **[`systemd-repart`](https://www.freedesktop.org/software/systemd/man/latest/systemd-repart.html)** - prepares signable read‑only disk images for the builder and resizes and re‑encrypts the state partition at each boot.
- **[Linux Unified Key Setup (`LUKS`)](https://gitlab.com/cryptsetup/cryptsetup/blob/master/README.md)** - encrypts the state partition with an ephemerally generated key on each boot.
- Various **build requirements** for Android, such as Python 3 and OpenJDK. The complete list is in the `packages` section of `android-build-env.nix`.

A complete **Software Bill of Materials (SBOM)** for the builder's NixOS closure can be generated from the repository root by running, e.g.:

``` shellsession
nix run github:tiiuae/sbomnix#sbomnix -- .#nixosConfigurations.vm.toplevel
```


# Major Components

The **NixOS Android Builder** is a collection of Nix expressions (a "nix flake") and helper scripts that produce a reproducible[^reproducible], ready‑to‑flash Linux system capable of compiling Android Open Source Project (AOSP) code.
The flake pins `nixpkgs` to a specific commit, ensuring that the same versions of compilers, libraries, and build tools are used on every build.
Inside the flake, a NixOS module describes the system layout, the `android-build-env` package, and the custom `fhsenv` derivation that provides conventional Linux file system hierarchy.
This approach guarantees that the same inputs always generate the same output, making the build process deterministic and auditable.

Users with `nix` installed can clone this repository, download all dependencies and build a signed disk image, ready to flash & boot on the build machine, in a few simple steps outlined in [README.md](../README.md).

The resulting disk image boots on generic `x86_64` hardware with `UEFI` as well as Secure Boot, and provides an isolated build environment.
It contains scripts for secure boot enrollment, a verified filesystem, and an ephemeral, encrypted state partition that holds build artifacts that cannot fit into memory.

[^reproducible]: *Reproducible* in functionality. The final disk images are not yet expected to be *fully* bit-by-bit reproducible. That could be done, but would require a long-tail of removing additional sources of indeterminism, such as as date & time of build. See [reproducible.nixos.org](https://reproducible.nixos.org/)

## Disk Image

A ready-made disk image to run NixOS Android Builder on a target host can be build from any existing `x86_64-linux` system with `nix` installed.
Under the hood, the image itself is built by `systemd-repart`, using NixOS module definitions from `nixpkgs` as well as custom enhancements shipped in this repository.

### Build Process

`systemd-repart` is called twice during build-time:

1. While building `system.build.intermediateImage`:
  A first image is built, it contains the `store` partition, populated with our NixOS closure as well as minimal `var-lib` partition.
  `boot` and `store-verity` remain empty during this step.

2. While building `system.build.finalImage`:
  Take the populated `store` partition from the first step, derive `dm-verity` hashes from them and write them into `store-verity`.
  The resulting `usrhash` is added to a newly built `UKI`, which is then copied to `boot`, to a path were the firmware finds it (`/EFI/BOOT/BOOTX86.EFI`).

3. The image then needs to be signed with a script outside a `nix` build process (to avoid leaking keys into the world-readable `/nix/store`. No `systemd-repart` is involved in this step. Instead we use `mtools` to read the `UKI` from the image, sign it and - together with Secure Boot update bundles, write it back to `boot` inside the image.

4. Finally, `systemd-repart` is called once more during run-time, in early boot at the start of `initrd`: The minimal `var-lib` partition, created in the first step above, is resized and encrypted with a new random key on each boot. That
key is generated just before `systemd-repart` in our custom `generate-disk-key.service`.

### Disk Layout

| Partition           | Label          | Format           | Mountpoint |
|---------------------+----------------+------------------+------------|
| **00‑esp**          | `boot`         | `vfat`           | `/boot`    |
| **10‑store‑verity** | `store-verity` | `dm-verity hash` | `n/a`       |
| **20‑store**        | `store`        | `erofs`          | `/usr`     |
| **30‑var‑lib**      | `var-lib`      | `ext4`           | `/var/lib` |

- **boot** – Holds the signed Unified Kernel Image (`UKI`) as an `EFI` application, as well as Secure Boot update bundles for enrollment. The partition itself is unsigned and mounted read‑only during boot.
- **store-verity** – Stores the `dm‑verity` hash for the `/usr` partition. The hash is passed as `usrhash` in the kernel command line, which is signed as part of the `UKI`.
- **store** – Contains the read-only Nix store,  bind‑mounted into `/nix/store` in the running system. The integrity of `/usr` is verified at runtime using `dm‑verity`.
- **var-lib** – A minimal, ephemeral state partition. See next section below.

Notably, the root filesystem (`/`) is, along with an optional writable overlay of the Nix store, kept entirely in RAM (`tmpfs`) and therefore not present in the image.
There's also no boot loader, because the `UKI` acts as an `EFI` application and is directly loaded by the hosts firmware.

### Ephemeral State Partition

The `/var/lib` partition is deliberately designed to be temporary and encrypted. Each time the system boots, a fresh key is generated and the partition is resized to match the current disk size. This ensures that sensitive build artifacts never persist beyond a single session, reducing the risk of leaking proprietary information or to introduce impurities between different builds.

### Secure Boot Support

Secure Boot is enabled by generating a set of keys that are stored unencrypted in a local `keys/` directory within the repository. Users must protect these keys and back them up. When a new image is signed, Secure Boot update bundles (`*.auth` files) are created for each target machine. These bundles are stored unsigned and unencrypted on the `/boot` partition. On boot, we check whether whe are in Secure Boot setup mode and, if so, enroll our keys. If Secure Boot is disabled, we display an error and fail early during boot.

## Sequence Chart

~~~mermaid
---
config:
  theme: 'neutral'
---
flowchart TB
    uefi["UEFI Firmware"]
    kernel["Kernel"]
    systemd-initrd["systemd"]

    check-secureboot["<b>(2)</b> Check Secure Boot status"]
    enroll-secureboot["Enroll Secure Boot keys"]
    reboot["Reboot"]
    halt["Display error & halt"]

    generate-disk-key["<b>(3)</b> Generate ephemeral encryption key"]
    systemd-repart["<b>(4)</b> Resize, Format and Encrypt state partition"]
    mount["<b>(5)</b> Mount read-only & state partitions"]
    build-android["<b>(7)</b> `fetch-android` & `build-android` are executed"]
    android-tools["Android Build Tools (`repo`, `lunch`, `ninja`, etc.)"]
    artifacts["<b>(8)</b> Built images are available in /var/lib/builder"]

    uefi -- <b>(1)</b> Verify & Boot --> uki
    subgraph uki["Unified Kernel Image"]
      direction TB
      kernel --> initrd
      subgraph initrd["Initial RAM Disk"]
        direction TB
        systemd-initrd --> check-secureboot
        check-secureboot -- setup --> enroll-secureboot
        check-secureboot -- disabled --> halt
        check-secureboot -- active --> generate-disk-key
        generate-disk-key --> systemd-repart
        systemd-repart --> mount
        enroll-secureboot --> reboot
      end
    end
    uki -- <b>(6)</b> Switch into NixOS --> nixos
    subgraph nixos["Booted NixOS"]
      direction TB
      build-android --> android-tools
      android-tools --> artifacts
    end
~~~

### Description

1. The hosts EFI firmware boots into the Unified Kernel Image (`UKI`), verifying its cryptographic signature if secure boot is active. A service to check that Secure Boot is active runs early in the `UKI`s initial RAM disk (`initrd`).

2. `ensure-secure-boot-enrollment.services`, asks EFI firmware about the current Secure Boot status.
  - If it is **active** and our image is booting succesfully, we trust the firmware here and continue to boot normally.
  - If it is in **setup** mode, we enroll certificates stored on our ESP. Setting the platform key disables setup mode automatically and reboot the machine right after.
  - If it is **disabled** or in any unknown mode, we halt the machine but don't power it off to keep the error message readable.
3. Before encrypting the disks, we run `generate-disk-key.service`. A simple script that reads 64 bytes from `/dev/urandom` without ever storing it on disk. All state is encrypted with
   that key, so that if the host shuts down for whatever reason - including sudden power loss - the encrypted data
   ends up unusable.
4. `systemd-repart` searches for the small, empty state partition on its boot media and resizes it before using `LUKS` to
   encrypt it with the ephemeral key from **(2)**.
5. We proceed to mount required file systems:
   * A read-only `/usr` partition, containing our `/nix/store` and all software in the image, checked by `dm-verity`.
   * Bind-mounts for `/bin` and `/lib` to simulate a conventional, FHS-based Linux for the build.
   * An ephemeral `/` file system (`tmpfs`)
   * `/var/lib` from the encrypted partition created in **(3)**.
6. With all mounts in place, we are ready to finish the boot process by switching into Stage 2 of NixOS.
7. With the system fully booted, we can start the build in various ways. The current implementation still
   includes an inteactive shell and 2 demo scripts which can be used as a starting point:
      * `fetch-android` uses Androids `repo` utility to clone the latest `AOSP` release from `android.googlesource.com` to `/var/lib/build/source`.
   * `build-android` sources required environment variables before building a minimal `x86_64` `AOSP` image.
8. Finally, build outputs can be found in-tree, depending on the targets built.
   E.g. `/var/lib/build/source/out/target/product/vsoc_x86_64_only`. Those are currently not persisted on the builder, so manual copying is required if build outputs should be kept.

# Options Reference

{{nixos-options}}
