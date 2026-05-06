# Architecture

## Goal

Make Go a first-class language for writing **native L4Re tasks**.

A "native L4Re task" is an L4 process that runs directly on top of the L4Re
runtime services (sigma0, moe, ned, etc.) on the Fiasco microkernel — *not* a
baremetal guest running inside the `uvmm` virtual machine monitor.

The bridge between Go and the L4Re world is
[tamago](https://github.com/usbarmory/tamago). tamago consists of two pieces:
a modified Go toolchain (`usbarmory/tamago-go`) that adds `GOOS=tamago`, and
a Go library (`usbarmory/tamago`, vendored here as a submodule under
`third_party/tamago` with the fork branch `mynetz/tamago#l4re-native`)
containing per-target overlays for the `runtime/goos` interface.

The approach is the same one [`go-boot`](https://github.com/usbarmory/go-boot)
uses to run as a tamago unikernel under UEFI: a small Go package
(`user/l4re`, planned in iteration 2b) hosts the ELF entry point
(`cpuinit`), saves the initial environment handed in by the L4Re loader,
and provides Go-side bindings that issue L4 IPC directly via a Go-asm
syscall trampoline. There is no libl4re linkage and no cgo; the resulting
ELF is a fully static tamago binary that ned/moe load like any other L4Re
task.

The structural mapping to `go-boot` is one-to-one: where `go-boot`'s
`callFn` does a UEFI C-ABI function-pointer call against the SystemTable,
our trampoline issues a Fiasco syscall (kernel trap) carrying L4 IPC
message registers in the UTCB. Service tables (`SystemTable`/`l4re_env_t`)
and dispatch (function pointer / capability index) differ; the build
pattern, `linkcpuinit` / `linkramstart` / `linkprintk` extension points,
and Go-side marshalling style are unchanged. See
[`tamago.md`](./tamago.md) for the per-file translation table.

See [`tamago.md`](./tamago.md) for the toolchain wiring and
[`apps.md`](./apps.md) for how application code lives under `apps/`.

## Why not uvmm?

`uvmm` is L4Re's VMM for hosting full guest kernels (Linux, Zephyr, FreeRTOS).
Running tamago Go application baremetal would work, but this project intends
to enable a Go environment as a L4Re application.

This allow writing servers (and drivers) in Go.

Native L4Re tasks expose the full L4Re API surface to Go and let Go programs
participate as first-class citizens in capability-based composition.

## Layering

```
+------------------------------------------------------------+
|  Go application (apps/<name>/main.go)                      |
+------------------------------------------------------------+
|  Go runtime (tamago-go: GC, scheduler, goroutines)         |
+------------------------------------------------------------+
|  user/l4re overlay (planned, iteration 2b):                |
|    - cpuinit (Go-asm ELF entry; saves l4re_env_t from      |
|      initial register handoff)                             |
|    - linknamed Printk/RamStart/RamSize overrides           |
|    - Go-asm l4_ipc() trampoline (kernel trap)              |
|    - Go-side IPC marshalling (Vcon::write, etc.)           |
|  -- structurally identical to go-boot/uefi/x64/ --         |
+------------------------------------------------------------+
|  L4Re runtime services (sigma0, moe, ned, cons, io, ...)   |
+------------------------------------------------------------+
|  Fiasco microkernel                                        |
+------------------------------------------------------------+
|  Hardware (or QEMU for development)                        |
+------------------------------------------------------------+
```

## State

See [`roadmap.md`](./roadmap.md) for planned iterations.
