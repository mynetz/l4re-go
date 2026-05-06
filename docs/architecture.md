# Architecture

## Goal

Make Go a first-class language for writing **native L4Re tasks**.

A "native L4Re task" is an L4 process that runs directly on top of the L4Re
runtime services (sigma0, moe, ned, etc.) on the Fiasco microkernel — *not* a
baremetal guest running inside the `uvmm` virtual machine monitor.

The bridge between Go and the L4Re world is
[tamago](https://github.com/usbarmory/tamago): a fork of the upstream Go
toolchain that emits **bare-metal Go binaries** (no host OS, no syscalls into
Linux). tamago programs run on a small assembly/C entry stub that brings up
the runtime, then hand off to `runtime.rt0_*`.

In our context, that entry stub is provided by the L4Re-side glue (loader,
ELF entry point, IPC bindings) so the resulting binary behaves like any other
L4Re task to sigma0/moe/ned.

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
|  Go application (compiled with tamago)                     |
+------------------------------------------------------------+
|  Go runtime (tamago: GC, scheduler, goroutines)            |
+------------------------------------------------------------+
|  L4Re glue:                                                |
|    - C/asm entry stub (_start -> runtime.rt0_*)            |
|    - IPC bindings (capabilities, dataspaces, ned)          |
|    - syscall shim (where Go runtime expects "OS")          |
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
