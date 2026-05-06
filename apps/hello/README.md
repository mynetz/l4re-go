# apps/hello

Minimal Go application targeting L4Re via tamago.

## Status

This is the **iteration 2a** form of the application: it imports the
upstream `github.com/usbarmory/tamago/user/linux` overlay, builds with
`GOOS=tamago` against the tamago-go toolchain, and runs as a normal Linux
process. Its purpose is to validate the toolchain wiring end-to-end before
introducing L4Re-specific runtime glue.

Iteration 2b will swap the overlay import for `user/l4re` (added on the
`l4re-native` branch of the `mynetz/tamago` submodule under
`third_party/tamago/`) and add an in-tree L4Re pkg that loads the resulting
ELF as a native L4Re task. See `docs/tamago.md` and `docs/roadmap.md`.

## Build & run (host smoke test)

```sh
task tamago:ensure        # one-time: submodule + wrapper + tamago-go toolchain
task apps:hello:build     # produces output/build/apps/hello/x86_64/hello
task apps:hello:run       # invokes the binary; prints the hello line
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
