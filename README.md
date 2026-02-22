# OpenCode Port for OpenBSD

OpenBSD-focused build, test, and release orchestration for running OpenCode with a patched Bun toolchain.

Status (tested baseline from Feb 21, 2026):
- OpenCode baseline commit (openbsd-host snapshot): `7b078bc`
- Stable branch: `stable/openbsd-0.1`
- Stable tag: `openbsd-stable-20260221`

## What This Repo Contains

This is the orchestration/documentation repo. It contains:
- porting docs and status
- build and test scripts
- patching helpers
- publication and release planning

It does **not** vendor the full Bun/OpenCode source histories or compiled binaries.

## Related Repos (publish snapshots on OpenBSD host)

- `bun-openbsd` (patched Bun source repo snapshot)
- `opencode-openbsd` (patched OpenCode source repo snapshot)

## Prerequisites

- macOS machine for codegen/cross-compilation orchestration (current docs assume a Mac host)
- OpenBSD 7.8 amd64 host for native linking/runtime validation
- SSH access to your OpenBSD host
- `tmux` on OpenBSD for visible TUI test runs

## Quick Start (Maintainer / Porter Path)

1. Read `PLACEHOLDERS.md` and map placeholders to your host/workspace names.
2. Read `OPENCODE-PORT-BUILD-GUIDE.md` for the full build pipeline.
3. Run baseline validation from this repo:
   - `./scripts/test/run-openbsd-baseline.sh <your-openbsd-host>`
4. Run visible TUI tests in tmux:
   - `./scripts/test/run-visible-tui-tests.sh <your-openbsd-host>`

## End-User Install Status

`pkg_add` installation is **not available yet**.

Current usable path is source/build validation with the Bun/OpenCode port snapshots. Official `pkg_add` availability requires OpenBSD ports acceptance and successful bulk builds.

## Layout

- `scripts/build/` build helpers and wrappers
- `scripts/test/` baseline and visible TUI tests
- `scripts/tools/` patching/binary utilities
- `PLAN.md` detailed engineering log and state
- `PORT-STATUS.md` concise current status
- `PUBLISHING-AND-PORTS-PLAN.md` publishing + ports strategy

## Branching / Release Model

- `main`: active development
- `stable/openbsd-0.1`: stable branch for consumers
- tags: tested snapshots like `openbsd-stable-YYYYMMDD`

## OpenBSD Ports / `pkg_add`

There is no separate package-name claim system. A package name becomes real when the port is accepted into the OpenBSD ports tree and built on bulk infrastructure.
