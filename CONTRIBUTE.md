# Contributing

This project spans three repositories:
- `openbsd-opencode-port` (docs/scripts/packaging workflow)
- `opencode-openbsd` (OpenCode fork with OpenBSD fixes)
- `bun-openbsd` (Bun fork with OpenBSD fixes)

## Where Changes Go

- `openbsd-opencode-port`: docs, maintainer scripts, packaging/ports workflow
- `opencode-openbsd`: OpenCode/OpenTUI/OpenBSD integration changes
- `bun-openbsd`: Bun runtime/toolchain/OpenBSD compatibility changes

Keep cross-repo changes split into reviewable commits.

## Before You Commit

1. Read `RELEASE.md` for current status and blockers.
2. Run baseline checks:
   - `./scripts/test/run-openbsd-baseline.sh <your-openbsd-host>`
3. Run visible TUI checks when UI/input/rendering is affected:
   - `./scripts/test/run-visible-tui-tests.sh <your-openbsd-host>`
4. Update docs when behavior or commands change.

## Branching / Publishing

### `openbsd-opencode-port`
- `main` is the active branch.

### `opencode-openbsd`
- `main`: integration branch
- `stable/openbsd-0.1`: stable consumer branch
- tags: tested snapshots (for example `openbsd-stable-YYYYMMDD`)

### `bun-openbsd`
- `main` is the active branch unless a stable branch is introduced

Push the same commits/tags to both remotes (`github`, `sourcehut`).

Example:

```sh
git push github main
git push sourcehut main
```

## Documentation Policy

Keep public docs:
- accurate
- concise
- free of local hostnames/paths/secrets

Use placeholders for environment-specific values (for example `<openbsd-host>`, `<workspace-root>`).
