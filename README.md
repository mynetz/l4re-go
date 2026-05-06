# l4re-go-prj

Enable Go as a programming language in L4Re by using
[tamago](https://github.com/usbarmory/tamago) as a bare-metal Go runtime that
runs **inside a native L4Re task** — not as a guest under uvmm.

This repository is the integration project that orchestrates the toolchain
(L4Re, Fiasco, tamago) via [Taskfile](https://taskfile.dev).

## Components

- L4Re Operating System Framework
- Fiasco microkernel
- tamago Go toolchain & library (`third_party/tamago` submodule, fork
  `mynetz/tamago` branch `l4re-native`)
- In-tree Go applications under `apps/`
- Taskfile — build/run orchestration

## Quick start

```sh
task bootstrap          # ham sync, build fiasco, build l4re
task qemu:run           # run hello-cfg in QEMU

task tamago:ensure      # init submodule, build tamago wrapper, fetch tamago-go
task apps:hello:build   # build apps/hello with GOOS=tamago
task apps:hello:run     # iteration 2a host smoke test
```

See [`docs/`](./docs) for architecture, build system, conventions, manifest
handling, tamago integration, application layout, and roadmap.
