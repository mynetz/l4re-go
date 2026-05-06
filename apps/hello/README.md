# apps/hello

Minimal Go application targeting L4Re via tamago.

## Status (current commit)

`main.go` imports `github.com/usbarmory/tamago/user/l4re`, the overlay
package added on the `l4re-native` branch of the `mynetz/tamago`
submodule under `third_party/tamago/`. The build pipeline produces an
ELF that L4Re's loader (ned/moe) can mount and start.

**`task apps:hello:qemu` does not yet print "Hello from Go on L4Re".**
The chain reaches the binary's `cpuinit` and transfers control to
`runtime.rt0_amd64_tamago` inside the tamago-go runtime, but Go's TLS
bring-up (`runtime.settls` in `tamago-go/src/runtime/sys_tamago_amd64.s`)
faults: at ring 3 it issues `syscall RAX=0x9e` expecting Linux's
`arch_prctl(ARCH_SET_FS)` semantics, which Fiasco does not serve.
Setting FS base on L4Re requires an L4 IPC to the main-thread
capability (`L4_THREAD_AMD64_SET_SEGMENT_BASE_OP`); `runtime.settls` is
emitted by the Go linker and has no `runtime/goos` extension point, so
the fix has to land in tamago-go itself.

This is tracked as iteration 2c in `docs/roadmap.md` and described in
detail in `docs/tamago.md`. The current commits (`8a2df82`, `55f9030`)
are explicitly tagged `[WIP]` for this reason.

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

## Build flags

The overlay overrides four tamago symbols, requiring the matching build
tags and linker entry override:

```
-tags linkcpuinit,linkramstart,linkramsize,linkprintk
-ldflags "-E cpuinit -T 0x10010000 -R 0x1000"
```

`task apps:hello:build` already passes these; you only need to know
about them if you build the app outside Taskfile.
