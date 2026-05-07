# Roadmap

Iterative plan for getting Go running as a native L4Re task via tamago.

## Iteration 1 — L4Re hello world via Taskfile

- Vendored ham manifest with `l4 → l4re` rename.
- Taskfile orchestration: `sources:*`, `fiasco:*`, `l4re:*`, `qemu:*`.
- Output layout under `output/build/<component>/<arch>/`.
- Default arch `x86_64`.
- Validation: `task bootstrap && task qemu:run` boots `hello-cfg` in QEMU.

No Go content yet. This iteration only proves the toolchain works.

## Iteration 2a — tamago toolchain checkpoint (current)

- Submodule `third_party/tamago` tracking `mynetz/tamago` branch
  `l4re-native`.
- Wrapper `tools/tamago-bin` built from `cmd/tamago` of the submodule via a
  consumer module (`apps/hello`), exec'ing the auto-fetched tamago-go SDK.
- `apps/hello/main.go` imports `github.com/usbarmory/tamago/user/linux`,
  compiles with `GOOS=tamago GOARCH=amd64`, runs as a normal Linux process.
- Taskfile namespaces `tamago:` and `apps:`; `task tamago:ensure` and
  `task apps:hello:build`/`run`.

This iteration deliberately does **not** run on L4Re yet; it validates the
toolchain, submodule, and build orchestration only.

## Iteration 2b — minimal Go-on-L4Re task (in progress)

Modelled on [`go-boot`](https://github.com/usbarmory/go-boot), a tamago
unikernel that talks to UEFI runtime services without cgo or libUEFI
linkage. We apply the same pattern to L4Re: pure Go + Go-asm, no libl4re,
no cgo. See [`docs/tamago.md`](./tamago.md) for the detailed translation
table.

- Add `user/l4re` overlay to the fork on the `l4re-native` branch,
  mirroring `go-boot/uefi/x64/`:
  - `l4re.s` defining `cpuinit` (`-E cpuinit`, `linkcpuinit` build tag)
    that saves the L4Re initial environment from the entry register
    convention, sets up RAM, jumps to `runtime·rt0_amd64_tamago`.
  - `l4re.go` providing `Init()` (linknamed to `runtime/goos.Hwinit1`),
    overriding `RamStart`/`RamSize`/`Printk` via `linkramstart,
    linkramsize, linkprintk` build tags.
  - `ipc.s` — Go-asm `l4_ipc()` trampoline issuing the Fiasco amd64
    syscall, equivalent in role to `go-boot/uefi/uefi.s` `callFn`.
  - `vcon.go` marshalling the `L4::Vcon::write` IPC for `printk`.
- In-tree L4Re pkg under `apps/hello/l4re-pkg/` (Control + Makefile +
  `hello-go.cfg`) installing the tamago-built ELF into the L4Re bin tree
  and registering a ned scenario.
- Goal: `task qemu:run SCENARIO=hello-go-cfg ...` boots and prints
  "Hello from Go on L4Re" on QEMU serial.

Estimated scope: ~400 lines of new Go + asm in the overlay, structurally
identical to `go-boot/uefi/x64/`. The L4Re-specific knowledge is narrow:
Fiasco amd64 syscall ABI, `l4re_env_t` layout, `L4::Vcon::write` opcode —
all documented in `sources/l4re/pkg/l4re-core/{l4sys,l4re}/include/`.

Current state: overlay package landed on the `l4re-native` branch of the
fork; tamago-built ELF is loaded by ned/moe; cpuinit runs and hands
control to the Go runtime, which then faults inside `runtime.settls`
because tamago-go's TLS bring-up assumes Linux's `arch_prctl(SET_FS)`
syscall semantics. Fiasco does not serve that ABI. Completing 2b
requires patching tamago-go (the toolchain), tracked as iteration 2c.

## Iteration 2c — tamago-go TLS hook for L4Re (in progress)

`runtime.settls` is emitted by the Go linker into every binary. Its
implementation lives in `tamago-go/src/runtime/sys_tamago_amd64.s` (only
on the per-version branches `tamago1.X.Y` of `usbarmory/tamago-go` —
`master` of that repo is plain upstream Go and contains no tamago
patches). The original implementation chose between WRMSR (ring 0) and
`syscall RAX=0x9e` (Linux `arch_prctl(SET_FS)`); both are unreachable
from an L4Re native task in ring 3.

This iteration introduces a portable hook that factors the OS-specific
FS_BASE installation into a `runtime/goos.SetTLSUser` symbol overrideable
by GOOSPKG-substituted overlays (matching the pattern already used for
`Hwinit0`, `Printk`, `RamStart`, etc.). The fork lives at
[mynetz/tamago-go](https://github.com/mynetz/tamago-go) on branch
`tamago1.26.2-l4re`.

### Patch summary (in tamago-go fork)

- `src/runtime/sys_tamago_amd64.s` — the `application:` branch of
  `runtime.settls` becomes `ADDQ $8, DI; CALL runtime/goos.SetTLSUser; RET`.
- `src/runtime/goos/linux_user_settls_amd64.go` (new) — forward-declares
  `func SetTLSUser(base uintptr)` for tamago/amd64 builds.
- `src/runtime/goos/linux_user_amd64.s` — provides the default
  `arch_prctl(ARCH_SET_FS)` body for Linux userspace builds (pure asm,
  caller-saved register discipline preserved).
- `src/runtime/goos/stub.go` — adds the godoc stub used for non-tamago
  builds.

The patch is 4 files, ~70 lines added. Verified backward-compatible:
`GOOS=tamago GOARCH=amd64` `fmt.Println` programs built with the patched
toolchain still run correctly under Linux userspace using the default
`runtime/goos` overlay (the `arch_prctl` path).

### L4Re overlay side (third_party/tamago, branch l4re-native)

- `goos/goos.go` declares `SetTLSUser(base uintptr)` in the tamago
  library's GOOSPKG-substituted `runtime/goos` package.
- `goos/goos_amd64.s` defines `runtime/goos.SetTLSUser` as
  `JMP setTLSUser(SB)`, mirroring how `runtime/goos.CPUInit` jumps to
  the overlay-supplied `cpuinit`.
- `user/l4re/settls_amd64.s` (new) provides `setTLSUser`: stages
  `MR[0]=0x12 (THREAD_SET_SEG_OP|FS=0)`, `MR[1]=base` in the UTCB at
  `gs:0`; reads `l4re_env_t.main_thread` (offset `0x20`) into the cap
  register; issues `SYSCALL` with the L4 IPC register convention
  (`RAX=msgtag`, `RDX=cap|L4_SYSF_CALL`, `RSI=0`, `R8=0`).

### `cmd/tamago` redirection

`third_party/tamago/cmd/tamago/main.go` is patched (on the
`l4re-native` submodule branch) to clone from `mynetz/tamago-go` at
branch `tamago<X.Y.Z>-l4re` instead of upstream `usbarmory/tamago-go` at
tag `tamago-go<X.Y.Z>`. The cache directory is named with an `-l4re`
suffix to coexist with any upstream-cached SDK.

### Status (this commit)

- Patched toolchain builds cleanly via `make.bash` (with
  `GOROOT_BOOTSTRAP` pointing at any cached tamago-go SDK).
- Patched toolchain produces working Linux userspace tamago binaries
  (verified: a `fmt.Println` test prints normally).
- Patched toolchain produces L4Re-targeted binaries that **load**, run
  cpuinit, return cleanly from `setTLSUser` (set_fs_base IPC), and pass
  the runtime's TLS self-test in `runtime.rt0_amd64_tamago` (no FATAL
  from l4re_itas).
- Execution then **silently stalls** somewhere in the post-TLS bring-up
  before reaching `main.main`. Suspected places: `runtime.osinit`,
  `runtime.schedinit`, or `runtime.mstart`'s scheduler loop, possibly
  due to incomplete clock/scheduler hooks in `user/l4re` (our
  `Nanotime` is a fake monotonic counter; `Idle`, `ProcID`, `Task` are
  unset). No exception is delivered, so the silent state is consistent
  with the runtime busy-waiting for some condition that never becomes
  true.

Next steps (deferred): instrument with QEMU's GDB stub or
`runtime.println` calls woven into the runtime's startup chain to find
the precise stall point, then either provide the missing hook or adjust
our overlay's nanotime/scheduler behaviour.

## Iteration 3 — IPC bindings

- Expose L4Re IPC primitives (capabilities, dataspaces, factory, named
  service lookup via `ned`) as Go packages.
- Demonstrate Go ↔ Go and Go ↔ C++ L4Re service communication.

## Iteration 4 — production hardening

- Multiple architectures (arm64 first-class).
- Garbage collector / scheduler interaction with L4Re scheduling.
- Memory management hooks (using L4Re dataspaces as Go heap backing).
- Test harness: `task test:integration` runs scenarios in QEMU and asserts
  on serial output.
