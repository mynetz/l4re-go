# tamago integration

[tamago](https://github.com/usbarmory/tamago) is a framework for compiling
unencumbered Go applications for bare-metal and userspace-of-an-OS targets.
This project uses it as the path to "Go on L4Re" via L4Linux-style
para-virtualisation: the Go runtime is compiled with `GOOS=tamago` and a
project-specific `runtime/goos` overlay implements the lowest-level OS
expectations against L4Re primitives.

## Two upstream repositories

| Repo | Role | Where it lives in this project |
|---|---|---|
| [`usbarmory/tamago`](https://github.com/usbarmory/tamago) | Go *library*: SoC/board/userspace overlays | submodule `third_party/tamago` (fork: [`mynetz/tamago`](https://github.com/mynetz/tamago), branch `l4re-native`) |
| [`usbarmory/tamago-go`](https://github.com/usbarmory/tamago-go) | Modified Go *toolchain* (compiler/linker/runtime adding `GOOS=tamago`) | auto-fetched by the helper `cmd/tamago` into `~/.cache/tamago-go/` |

## Bootstrap

Run once:

```sh
task tamago:ensure
```

That:

1. Initialises the submodule.
2. Builds `tools/tamago-bin` from `cmd/tamago`. **Important:** the wrapper
   has to be built from a *consumer module* (we use `apps/hello`) so its
   embedded build info pins the tamago library version. When invoked from
   the tamago module itself, `cmd/tamago` reports the version as `(devel)`
   and refuses to run.
3. Triggers the wrapper, which clones `tamago-go` at the matching tag and
   runs `make.bash`. Result: a full Go SDK at
   `~/.cache/tamago-go/tamago-go<X.Y.Z>/`.

## Why a wrapper binary instead of `go run` / `go tool tamago`?

`GOOS=tamago` is rejected by the **host** Go command at command-line parse
time, before any subcommand or tool is invoked. So `GOOS=tamago go run
.../cmd/tamago build ...` fails with `unsupported GOOS/GOARCH pair
tamago/amd64` — the host Go never gets to delegate.

The wrapper binary has no such check (it just calls `os.Args` and exec's the
cached tamago-go `go` with the right `GOROOT`). Running
`GOOS=tamago tools/tamago-bin build ...` therefore works.

## Build flow

`apps/hello/`'s `go.mod`:

```go
require github.com/usbarmory/tamago v1.26.2
replace github.com/usbarmory/tamago => ../../third_party/tamago
tool github.com/usbarmory/tamago/cmd/tamago
```

`task apps:hello:build` runs:

```sh
cd apps/hello && \
  GOOS=tamago GOARCH=amd64 \
  GOOSPKG=github.com/usbarmory/tamago \
  ../../tools/tamago-bin build -ldflags "-T 0x10010000 -R 0x1000" \
    -o ../../output/build/apps/hello/x86_64/hello .
```

`-T` sets the load address (Cloud Hypervisor / QEMU microvm convention from
upstream tamago).

## Iteration scope

### Iteration 2a (this commit) — toolchain checkpoint

`apps/hello/main.go` imports
`github.com/usbarmory/tamago/user/linux`. The resulting ELF is a Linux
process compiled with `GOOS=tamago`, running with the upstream userspace
overlay. It does **not** run on L4Re yet. It validates:

- the submodule + wrapper plumbing,
- tamago-go toolchain auto-fetch,
- the consumer-module `replace` pattern,
- the Taskfile ergonomics.

### Iteration 2b (planned) — native L4Re task

The next iteration replaces the import with
`github.com/usbarmory/tamago/user/l4re` (a new package added on the
`l4re-native` fork branch). The package is modeled directly on
[`go-boot`](https://github.com/usbarmory/go-boot), which is a tamago
unikernel that calls UEFI runtime services from pure Go without cgo or
libUEFI linkage.

#### Why go-boot is the right model

Earlier exploration hit a wall trying to link a C shim (calling L4Re's
libl4re) into a tamago binary: `-buildmode=c-archive` is unsupported on
`tamago/amd64`, and `-linkmode=external` requires cgo, which tamago
disables. `go-boot` sidesteps the problem entirely — it never links libUEFI.
Instead it talks the UEFI ABI directly:

- `cpuinit` is the ELF entry (set via the tamago linker flag `-E cpuinit`
  combined with the `linkcpuinit` build tag). UEFI hands the program
  control with `imageHandle` in `RCX` and `systemTable` in `RDX` per the
  UEFI 2.10 §2.3.4.1 amd64 calling convention. The Go-asm `cpuinit` saves
  these into Go-package globals, derives the `ConIn`/`ConOut` pointers from
  fixed offsets in the system table, sets up the runtime stack, then jumps
  to `runtime·rt0_amd64_tamago`.
- A tiny Go-asm trampoline (`callFn` in `uefi/uefi.s`) implements the UEFI
  C-ABI calling convention for amd64 (RCX, RDX, R8, R9 then stack, plus the
  32-byte shadow space and 16-byte stack alignment).
- Higher-level Go code in `uefi/console.go`, `uefi/uefi.go` etc. marshals
  arguments into `[]uint64`, picks the function-pointer offset
  (e.g. `ConOut + 0x08` for `OutputString`), and calls `callService(fn, args)`.
- The standard `runtime/goos` symbols `RamStart`, `RamSize`, `Printk` are
  overridden via the `linkramstart, linkramsize, linkprintk` build tags
  combined with `//go:linkname`; this is the official tamago hook for
  board / userspace overlays.

Result: a fully static tamago ELF, post-processed with `objcopy` into a
PE32+ EFI executable. No cgo, no external linker, no libUEFI dependency.

#### Translation to L4Re

The structural translation is one-to-one. Both UEFI and L4Re hand a
program a pointer to a service table at startup; the program then issues
calls into that table.

|                          | UEFI (go-boot)                                         | L4Re native task (planned)                                         |
| ------------------------ | ------------------------------------------------------ | ------------------------------------------------------------------ |
| Initial register handoff | `RCX = imageHandle`, `RDX = systemTable`               | First-arg register = `l4re_env_t *`; UTCB pointer in `gs:0`        |
| Service dispatch         | C-ABI call to a function pointer in `SystemTable`      | L4 IPC (kernel trap) to a capability index in `l4re_env_t`         |
| Console out              | `SystemTable->ConOut->OutputString(self, str)`         | IPC to the `log` cap implementing `L4::Vcon::write`                |
| Time                     | RTC + invariant TSC                                    | KIP clock field (memory read; no IPC needed)                       |
| Halt                     | `BootServices->Exit(...)` or `Runtime->ResetSystem()`  | `l4_sleep_forever()` (which is itself an IPC to the kernel)        |

The trampoline shape is what changes. `go-boot`'s `callFn` does a C-ABI
function-pointer call. Our `l4_ipc` will issue a Fiasco syscall (kernel
trap) with the L4 IPC opcode in a register and message registers in the
UTCB. Otherwise the package layout, the build tags, and the Go-side
marshalling pattern are unchanged.

#### Concrete file layout (mirrors go-boot)

| `user/l4re/` file (planned) | Counterpart in `go-boot` |
|---|---|
| `l4re.go` — board package, `Init()`, `Hwinit1`, RAM/clock setup | `uefi/x64/x64.go` |
| `l4re.s` — `cpuinit` entry: save initial env, set up stack, jump to runtime | `uefi/x64/x64.s` |
| `console.go` — `printk` linkname; `Console` writing to `log` cap | `uefi/x64/console.go` |
| `mem.go` — `RamStart`/`RamSize`; allocate via L4Re dataspace or fixed BSS | `uefi/x64/mem.go` |
| `ipc.s` — Go-asm `l4_ipc()` Fiasco syscall trampoline | `uefi/uefi.s` (`callFn`) |
| `vcon.go` — `L4::Vcon::write` opcode marshalling | `uefi/console.go` (`Output`, `Write`) |

Build flags will mirror go-boot's:

```
-tags linkcpuinit,linkramsize,linkramstart,linkprintk
-ldflags "-E cpuinit -T <addr> -R 0x1000"
```

The L4Re-specific knowledge needed is narrow:
1. Fiasco amd64 syscall ABI: the trap vector / register layout for L4 IPC.
2. `l4re_env_t` layout: offset of the `log_cap` field.
3. `L4::Vcon::write` IPC protocol: opcode in MR0, buffer/length in MRs.

All three are documented in
`sources/l4re/pkg/l4re-core/{l4sys,l4re}/include/` (available after
`task sources:sync`). Estimate: ~400 lines of Go + asm in the overlay,
plus a small in-tree L4Re pkg under `apps/hello/l4re-pkg/` (Control +
Makefile + `hello-go.cfg`) that copies the tamago-built ELF into the L4Re
bin tree and registers a ned scenario.
