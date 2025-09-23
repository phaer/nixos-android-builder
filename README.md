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

See [./docs/docs.md](docs.md) for a more detailed description of design considerations, used components and further work.
And [./docs/user-guide.md](user-guide.md) for a user guide, explaining usage.
