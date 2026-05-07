# apps/hello

Minimal Go application targeting L4Re via tamago.

## Status (current commit)

`main.go` imports `github.com/usbarmory/tamago/user/l4re`, the overlay
package added on the `l4re-native` branch of the `mynetz/tamago`
submodule under `third_party/tamago/`. The build pipeline produces an
ELF that L4Re's loader (ned/moe) can mount and start.

**`task apps:hello:qemu` does not yet print from `main`.** The chain
now successfully loads the binary, runs `cpuinit`, transfers control to
`runtime.rt0_amd64_tamago`, completes the runtime's TLS self-test
(thanks to the `runtime/goos.SetTLSUser` hook added in iteration 2c —
see `docs/settls-blocker.md` and `docs/roadmap.md`), and **then silently
hangs** somewhere in the post-TLS Go runtime startup chain
(`osinit`/`schedinit`/`mstart`) before `main.main` runs.

This is tracked as iteration 2c-bringup in `docs/roadmap.md`. The
current commit is explicitly tagged `[WIP]` for this reason.

## Build & run

```sh
task tamago:ensure        # one-time: submodule + wrapper + tamago-go SDK
task apps:hello:build     # produces output/build/apps/hello/x86_64/hello-go
task apps:hello:qemu      # boots the hello-go-cfg scenario in QEMU
                          # (will fault inside runtime.settls until 2c lands)
```

## Module layout

`go.mod` declares this directory as `l4re-go-prj/apps/hello` and pins
`github.com/usbarmory/tamago v1.26.2` (the upstream tag corresponding to
the submodule's `l4re-native` branch HEAD). A `replace` directive points
that import at `../../third_party/tamago` so any changes on the fork
branch are picked up automatically.

The `tool` directive in `go.mod` registers
`github.com/usbarmory/tamago/cmd/tamago` so the host Go can build it via
`go build` (Taskfile uses `task tamago:bin` to produce
`tools/tamago-bin`). The host's own `go tool tamago` cannot be used to
*invoke* the tamago build because the host Go refuses `GOOS=tamago` at
parse time; the wrapper binary side-steps this by exec'ing the cached
tamago-go `go` directly.

## Toolchain

This project uses a **forked tamago-go** at
[`mynetz/tamago-go`](https://github.com/mynetz/tamago-go) on branch
`tamago1.26.2-l4re`. The fork adds a `runtime/goos.SetTLSUser` hook to
factor the OS-specific TLS bring-up out of `runtime.settls`. Our
submodule's `cmd/tamago` is patched to clone from the fork; the SDK
caches under `~/.cache/tamago-go/tamago-go1.26.2-l4re/` (distinct from
any upstream tamago-go SDK in the same cache root).

If the host Go is older than 1.24.6, point `GOROOT_BOOTSTRAP` at any
existing tamago-go SDK before running `task tamago:ensure`; the
Taskfile's `tamago:toolchain:warm` rule does this automatically when it
finds `~/.cache/tamago-go/tamago-go1.26.2/` to bootstrap from.

## Build flags

The overlay overrides four tamago symbols, requiring the matching build
tags and linker entry override:

```
-tags linkcpuinit,linkramstart,linkramsize,linkprintk
-ldflags "-E cpuinit -T 0x10010000 -R 0x1000"
```

`task apps:hello:build` already passes these; you only need to know
about them if you build the app outside Taskfile.
