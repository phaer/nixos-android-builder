# NixOS Android Builder

This repository contains a custom Linux system to build Android Open Source Project in a (mostly) ephemeral environment. Our images, based on NixOS, provide a FHS-compatible enviroment that can run upstream Androids toolchain while being flexible and relatively easy to adapt due to the NixOS module system.

We boot into memory while keeping build state that's too big for memory in an ephemeral `/var/lib/build` partition on disk. That partition will be expanded and (re-)encrypted with a ephemeral key on each boot.
While no state is persisted between boots by default, there's an option to use a second disk as "artifact storage" to store build outputs in air-gapped environments.

See [user-guide.md](./docs/user-guide.md) for usage guidance and [docs.md](./docs/docs.md) for a more detailed description of design considerations, used components limitations, and further work.

