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

## Iteration 2b — minimal Go-on-L4Re task

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
