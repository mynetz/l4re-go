# Conventions

## Source directory naming

The L4Re source tree lives at **`sources/l4re/`**, not `sources/l4/`.

Upstream's manifest checks the L4Re tree out as `l4/` for historical reasons.
We rename it to `l4re/` for consistency.

The rename is applied in our **local manifest**
(`config/manifest/default.xml`) — see [`manifest.md`](./manifest.md).

## Build output naming

Build directories live under `output/build/<component>/<arch>/`:

```
output/build/l4re/x86_64/      # was: l4re_builds/x86_64/
output/build/fiasco/x86_64/    # was: fiasco_builds/x86_64/
```

This deviates from the upstream tutorial's `l4re_builds/<arch>` and
`fiasco_builds/<arch>` for two reasons:

1. **Single root for everything generated.** `output/` holds *all* build
   artifacts (and any future intermediate directories), so `task clean` /
   `task distclean` can target one tree.
2. **Component grouped first, arch second.** Makes it natural to extend with
   future components (`output/build/tamago/`, `output/build/glue/`, …) while
   keeping per-arch parallel builds.

## Top-level layout

```
l4re-go-prj/
├── Taskfile.yml                # entry point
├── taskfiles/                  # included sub-taskfiles
├── config/                     # tracked, hand-edited configuration
│   └── manifest/default.xml
├── docs/                       # agent-consumable documentation
├── tools/                      # auto-managed helpers (gitignored)
│   └── ham/                    # cloned only if system ham is missing
├── sources/                    # gitignored; populated by `task sources:sync`
└── output/                     # gitignored; all build artifacts
    └── build/<component>/<arch>/
```

## What is tracked vs. ignored

Tracked: `Taskfile.yml`, `taskfiles/`, `config/`, `docs/`, `README.md`,
`.gitignore`.

Ignored: `sources/`, `output/`, `tools/ham/`, `.task/`.

## Task naming

- Namespaces match components: `sources:`, `fiasco:`, `l4re:`, `qemu:`.
- Each component exposes a consistent verb set where applicable: `init`,
  `build`, `config`, `clean`.
- Top-level meta tasks: `bootstrap`, `clean`, `distclean`, `default`.

## Architecture parameter

`ARCH` is the single source of truth for target architecture and propagates
to both `KERNEL_OBJDIR` and `L4RE_OBJDIR`. To build for a different arch,
override at invocation time: `task ARCH=arm64 bootstrap`. Switching arch
requires `make config` in each build dir to reconfigure (or starting from a
clean build dir).
