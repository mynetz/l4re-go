# Vendored ham manifest

## Why we vendor

`ham` (the L4Re multi-repo tool) drives source-tree layout from a manifest
XML. Upstream's manifest checks the L4Re source tree out at `l4/`. We want
`l4re/` instead (see [`conventions.md`](./conventions.md)), and we want the
freedom to customise the manifest later without forking on GitHub.

So we keep a vendored copy in tree at:

```
config/manifest/default.xml
```

`ham init --file <path>` reads a local manifest directly — no remote URL or
intermediate git repo required.

## Transformations vs upstream

The vendored copy is identical to upstream
(<https://github.com/L4Re/manifest/blob/main/default.xml>) except for two
changes:

### 1. Path renames (`l4` → `l4re`)

| Upstream                | Vendored                   |
| ----------------------- | -------------------------- |
| `path="l4"`             | `path="l4re"`              |
| `path="l4/pkg/<name>"`  | `path="l4re/pkg/<name>"`   |
| `path="fiasco"`         | `path="fiasco"` (unchanged)|

### 2. Absolute `<remote fetch=...>` URL

Upstream sets `fetch=".."`, which is resolved relative to the manifest
repository's URL. Because we feed ham a local file via `ham init -f`, ham
has no manifest URL to resolve `..` against, and `git clone` fails with
paths like `/../mk`. We therefore set the `fetch` (and `review`) attribute
to the absolute base URL of the L4Re GitHub organisation:

```xml
<remote name="origin"
        fetch="https://github.com/L4Re"
        review="https://github.com/L4Re" />
```

The header comment in `config/manifest/default.xml` records the upstream
URL, branch, commit SHA, and fetch date.

## Workflows

### Run sync (normal usage)

```sh
task sources:sync
```

Idempotent. First run runs `ham init --file ...` and `ham sync`; subsequent
runs only `ham sync`.

### Re-sync after editing the manifest

If you edit `config/manifest/default.xml` (e.g. pin a project to a specific
revision, add a project, exclude one) and the *paths* did not change:

```sh
task sources:manifest:refresh
```

If the *paths changed* (renames, removals), the safest path is:

```sh
task sources:reset
```

This deletes `sources/` and re-creates it from scratch.

### Bumping upstream

1. Fetch the current upstream manifest:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/L4Re/manifest/main/default.xml \
        -o /tmp/upstream-default.xml
   ```

2. Diff against ours, accounting for the `l4 → l4re` rename:

   ```sh
   diff <(sed 's|path="l4/|path="l4re/|g; s|path="l4"|path="l4re"|g' \
              /tmp/upstream-default.xml) \
        config/manifest/default.xml
   ```

3. Apply any new/changed `<project ...>` lines from upstream into ours,
   preserving the `l4re` rename for new entries.

4. Update the header comment in `config/manifest/default.xml` with the new
   upstream commit SHA and fetch date.

5. `task sources:manifest:refresh` (or `task sources:reset` for path
   changes).

## Why not a symlink?

Earlier we considered letting ham create `sources/l4/` and adding a
`sources/l4re -> l4` symlink. Rejected because:

- Future `ham sync` could regenerate `l4/` and leave the symlink stale or
  broken.
- Tools that resolve realpaths (IDE indexers, build artifact tracking)
  would see two names for the same tree.
- Vendoring the manifest is a stronger primitive that we already need for
  later customisation (pinning, excluding, adding projects).
