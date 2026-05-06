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

### Branch / tag layout of `usbarmory/tamago-go`

Browsing `usbarmory/tamago-go` is initially confusing: `master` is a
straight mirror of upstream `golang/go` and contains **no** tamago
patches. The actual tamago-modified Go distribution lives on per-version
branches and is published as tags. As of 2026-05 the relevant refs are:

```
refs/heads/master        plain upstream Go (no tamago changes)
refs/heads/tamago1.26.2  tamago-patched runtime/compiler for Go 1.26.2
refs/tags/tamago-go1.26.2  same commit, tagged for cmd/tamago
refs/tags/latest         alias to the most recent tamago-goX.Y.Z tag
```

`cmd/tamago` calls `git clone --depth=1 --branch=tamago-go<X.Y.Z>
https://github.com/usbarmory/tamago-go ~/.cache/tamago-go/tamago-go<X.Y.Z>`
where `<X.Y.Z>` comes from the consumer module's `require
github.com/usbarmory/tamago` line. The cached SDK therefore *does*
contain the tamago-patched files (`src/runtime/sys_tamago_amd64.s`,
`src/runtime/goos/`, `src/runtime/rt0_tamago_*.s`, etc.); only the
`master` branch on the upstream repo lacks them.

The Go upstream proposal [golang/go#73608][73608] tracks the long-term
goal of folding this work into `GOOS=none`. The tamago-go branches are
the working implementation; the proposal text and supplementary links
live on the issue.

[73608]: https://github.com/golang/go/issues/73608

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

### Iteration 2b (in progress) — native L4Re task

The `user/l4re` overlay package now exists in the submodule on branch
`l4re-native`. It implements the package layout described below and
builds cleanly. End-to-end QEMU validation is **not yet** functional;
execution stalls inside the Go runtime's TLS bring-up, see "Status" at
the end of this section.

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
`task sources:sync`). The current overlay totals ~250 lines of Go + asm.

The L4Re pkg is currently *not* a real L4Re pkg under `sources/l4re/pkg/`.
Instead, the integration repo carries a small `apps/hello/l4re-pkg/`
directory containing only `modules.list` and `hello-go.cfg`. The
tamago-built ELF is dropped into `output/build/apps/hello/x86_64/` and
exposed via `MODULE_SEARCH_PATH` to L4Re's `make E=hello-go-cfg qemu`.
This avoids modifying the ham-managed `sources/l4re/` tree.

#### Status (this commit)

- `task apps:hello:build` produces `output/build/apps/hello/x86_64/hello-go`
  (~10 MB, includes 8 MiB BSS pad for the runtime heap).
- `task apps:hello:qemu` boots: bootstrap → fiasco → sigma0 → moe → ned
  loads the binary and jumps to its ELF entry. `cpuinit` runs and
  successfully transfers control to `runtime.rt0_amd64_tamago` inside the
  tamago-go runtime.
- Execution then faults inside `runtime.settls` (defined in
  `tamago-go/src/runtime/sys_tamago_amd64.s`). At ring 3 (userspace), that
  routine issues `syscall` with `RAX = 0x9e` (Linux `arch_prctl`,
  `ARCH_SET_FS = 0x1002`). Fiasco interprets `syscall` as the L4 IPC
  vector, returns garbage, and the subsequent `%fs:-8` access faults.
- Setting the FS base on L4Re requires an L4 IPC to the thread capability
  (`L4_THREAD_AMD64_SET_SEGMENT_BASE_OP = 0x12`, `L4_PROTO_THREAD = -12`,
  segment selector `L4_AMD64_SEGMENT_FS = 0`, base in `MR[1]`,
  `l4_ipc_call` to `l4re_env_t.main_thread`). Doing this from cpuinit
  alone is insufficient because tamago-go's runtime calls `settls` again
  during world bring-up, which would clobber any FS base we pre-set.
- Resolving this cleanly requires patching tamago-go itself: either add a
  `runtime/goos` hook for `settls`, or replace the inlined
  `arch_prctl`/`WRMSR` body in `sys_tamago_amd64.s` with a call into the
  overlay-provided L4 IPC helper. That patch is outside the scope of the
  library-side overlay and pushes the work into the next iteration.

In the meantime the overlay code on branch `l4re-native` of
[mynetz/tamago](https://github.com/mynetz/tamago) and the in-tree
`apps/hello/l4re-pkg/` artefacts stand as a checkpoint that exercises
everything except the final TLS bring-up.
