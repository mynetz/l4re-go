# Adding a Go app

Go applications targeting L4Re live under `apps/<name>/`. Each app is a
self-contained Go module so the tamago wrapper binary can be built from
its consumer-module build info (see `docs/tamago.md` for why this matters).

## Layout

```
apps/<name>/
├── README.md       # short app description, status
├── main.go         # entry point
├── go.mod          # pins github.com/usbarmory/tamago, replaces -> third_party/tamago
├── go.sum          # tracked
└── l4re-pkg/       # (iteration 2b+) Control + Makefile + .cfg
```

Output:

```
output/build/apps/<name>/<arch>/<binary>
```

## go.mod template

```go
module l4re-go-prj/apps/<name>

go 1.26.2

require github.com/usbarmory/tamago v1.26.2

replace github.com/usbarmory/tamago => ../../third_party/tamago
tool github.com/usbarmory/tamago/cmd/tamago
```

The `require` version must match the upstream tag the submodule HEAD
corresponds to. `cmd/tamago` reads it from the wrapper's build info to
choose which `tamago-go` release to pull.

## Taskfile additions per app

Mirror the `apps:hello:*` tasks in `taskfiles/apps.yml` for each new app.
Common variables (`APPS_OUT`) are shared.

## Build & run

```sh
task tamago:ensure         # one-time, host-side
task apps:<name>:build     # produces the ELF
task apps:<name>:run       # iteration 2a only: host-side smoke test
```

Iteration 2b will add `task apps:<name>:l4re` to install the binary into
the L4Re tree, plus a per-app `hello-go.cfg`-style ned scenario.
