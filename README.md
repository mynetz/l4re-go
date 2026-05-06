# l4re-go-prj

Enable Go as a programming language in L4Re by using
[tamago](https://github.com/usbarmory/tamago) as a bare-metal Go runtime that
runs **inside a native L4Re task** — not as a guest under uvmm.

This repository is the integration project that orchestrates the toolchain
(L4Re, Fiasco, tamago) via [Taskfile](https://taskfile.dev).

## Components

- L4Re Operating System Framework
- Fiasco microkernel
- tamago Go runtime (planned, future iteration)
- Taskfile — build/run orchestration

## Quick start

```sh
task bootstrap   # ham sync, build fiasco, build l4re
task qemu:run    # run hello-cfg in QEMU
```

See [`docs/`](./docs) for architecture, build system, conventions, manifest
handling, tutorial mapping, and roadmap.
