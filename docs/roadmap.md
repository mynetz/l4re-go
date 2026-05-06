# Roadmap

Iterative plan for getting Go running as a native L4Re task via tamago.

## Iteration 1 — L4Re hello world via Taskfile (current)

- Vendored ham manifest with `l4 → l4re` rename.
- Taskfile orchestration: `sources:*`, `fiasco:*`, `l4re:*`, `qemu:*`.
- Output layout under `output/build/<component>/<arch>/`.
- Default arch `x86_64`.
- Validation: `task bootstrap && task qemu:run` boots `hello-cfg` in QEMU.

No Go content yet. This iteration only proves the toolchain works.

## Iteration 2 — tamago toolchain

- Vendor or pin the tamago Go toolchain (it is upstream Go + patches).
- Add `tools:tamago` task that builds / unpacks the toolchain into
  `tools/tamago/` (gitignored).
- Add `tamago:build` task that builds a trivial Go program with tamago and
  produces an ELF binary suitable for L4Re loading.

## Iteration 3 — minimal Go-on-L4Re task

- Write a thin C/asm glue layer that:
  - Provides `_start` and the L4Re initial environment hand-off.
  - Calls tamago's runtime entry (`runtime.rt0_*`).
  - Stubs out the Go runtime's "OS" expectations (clock, memory, console).
- Package it as an L4Re pkg (e.g. `sources/l4re/pkg/go-hello/`) consumable
  by L4Re's existing build system.
- Run it as an L4Re task in `hello-cfg`-style QEMU scenario; goal: print
  "Hello from Go" via L4Re cons.

## Iteration 4 — IPC bindings

- Expose L4Re IPC primitives (capabilities, dataspaces, factory, named
  service lookup via `ned`) as Go packages.
- Demonstrate Go ↔ Go and Go ↔ C++ L4Re service communication.

## Iteration 5 — production hardening

- Multiple architectures (arm64 first-class).
- Garbage collector / scheduler interaction with L4Re scheduling.
- Memory management hooks (using L4Re dataspaces as Go heap backing).
- Test harness: `task test:integration` runs scenarios in QEMU and asserts
  on serial output.
