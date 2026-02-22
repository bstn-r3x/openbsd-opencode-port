# OpenCode on OpenBSD: Orchestration and Porting Manual

This is the **orchestration/documentation repository** for the OpenBSD porting work.

It is the entry point for:
- build and test procedures
- operator runbooks
- release/publishing workflow
- project status and known limitations

It is **not** an installable package repository and does **not** contain full source histories or compiled binaries.

## Current Status (Feb 21, 2026 baseline)

- OpenCode OpenBSD baseline commit: `7b078bc` (in `opencode-openbsd`)
- Stable branch: `stable/openbsd-0.1`
- Stable tag: `openbsd-stable-20260221`
- `pkg_add` availability: **not available yet** (not in official OpenBSD ports)

## What This Repo Is For

Use this repo when you need to:
- reproduce the build and validation workflow
- run regression tests on an OpenBSD host
- understand which docs are current vs historical
- prepare releases and public publication
- coordinate the `bun-openbsd` and `opencode-openbsd` repos

## Related Repositories

This project is split into three repos:

1. `openbsd-opencode-port` (this repo)
   - orchestration docs, scripts, runbooks, publish workflow
2. `bun-openbsd`
   - Bun source snapshot/fork with OpenBSD porting changes
3. `opencode-openbsd`
   - OpenCode source snapshot/fork with OpenBSD-specific fixes and tested tag/branch

## Audience and Expectations

### End users

This project is **not yet** a normal end-user install path.

- There is no official OpenBSD package in ports yet
- `pkg_add` does not work because the port is not accepted upstream
- Current usage is a porter/developer workflow (source + build/test)

### Porters / maintainers

This repo is designed for you. Start here, follow the docs in order below, and use the scripts to reduce manual steps.

## Read This First (Canonical Order)

Use docs in this order. This avoids getting lost in historical notes.

1. `README.md` (this file)
   - project shape, repo split, action sequence
2. `PLACEHOLDERS.md`
   - maps sanitized placeholders (for host/path names) used in docs
3. `PORT-STATUS.md`
   - current state, verified status, risks, non-blocking issues
4. `OPENCODE-PORT-BUILD-GUIDE.md`
   - full build pipeline (macOS + OpenBSD)
5. `COMPREHENSIVE-TEST-PLAN.md`
   - regression and interactive validation plan
6. `PUBLISHING-AND-PORTS-PLAN.md`
   - GitHub/SourceHut publishing and OpenBSD ports path

## Historical / Deep-Dive Docs (Not First-Read)

These files are useful, but they are not the fastest path to operating the project.

- `PLAN.md`
  - large engineering log with mixed historical states, patches, and experiments
- `ENTER-SUBMIT-FIX-PLAN.md`
  - focused investigation for a specific TUI Enter-submit bug (already fixed)
- `FINISH-PLAN.md`
  - execution checklist from a specific cleanup/normalization phase
- `WORKSPACE-STRUCTURE.md`
  - local workspace organization notes and compatibility symlinks

## Repository Contents (and Non-Contents)

Included here:
- markdown documentation and runbooks
- `scripts/build/*` build helpers/wrappers
- `scripts/test/*` baseline and visible TUI test scripts
- `scripts/tools/*` patching/binary utilities

Not included here:
- full Bun/OpenCode source trees
- `node_modules`, build outputs, caches
- compiled binaries (`bun`, `opencode-bin`, toolchains)
- local auth/session data, secrets, SSH keys
- private machine-specific runtime dumps

## Prerequisites

### Required machines

- macOS host for codegen and cross-compilation orchestration
- OpenBSD 7.8 amd64 host for native linking and runtime validation

### Required access/tools

- SSH access to the OpenBSD host
- `tmux` installed on the OpenBSD host (for visible TUI testing)
- ability to clone all three repos
- enough disk space for Bun + OpenCode builds and artifacts

## Recommended Local Layout

The docs assume the following logical layout (names can vary if you set environment variables/placeholders):

- macOS workspace root: `<MAC_WORKSPACE>/opencode-port`
- OpenBSD workspace root: `/srv/opencode-port`

The orchestration repo can live anywhere, but keeping the documented paths reduces friction.

## Operator Sequence (Comprehensive, Practical)

This is the intended sequence for maintainers.

### Phase 1: Clone and orient

1. Clone all three repositories:
   - `openbsd-opencode-port`
   - `bun-openbsd`
   - `opencode-openbsd`
2. Read `PLACEHOLDERS.md` and map placeholder names to your real host/path names.
3. Read `PORT-STATUS.md` to confirm current reality before acting on older docs.

### Phase 2: Prepare environment

1. Confirm SSH access to your OpenBSD host.
2. Confirm `tmux` is installed on OpenBSD.
3. Place Bun/OpenCode repos in the paths expected by your workflow (or export overrides for scripts).
4. Review `OPENCODE-PORT-BUILD-GUIDE.md` prerequisites before attempting rebuilds.

### Phase 3: Baseline validation (before changing code)

Run the baseline script from this repo:

```sh
./scripts/test/run-openbsd-baseline.sh <your-openbsd-host>
```

Optional environment overrides:

```sh
OPENCODE_PORT_HOST=<your-openbsd-host> OPENCODE_PORT_REMOTE_ROOT=/srv/opencode-port ./scripts/test/run-openbsd-baseline.sh
```

What this validates (high level):
- SSH connectivity and remote info
- Bun runtime smoke checks
- OpenCode source-mode help/liveness checks
- compiled binary presence/version (if present)

### Phase 4: Visible TUI testing (manual verification)

Start source-mode and compiled-mode TUI sessions in tmux windows on the OpenBSD host:

```sh
./scripts/test/run-visible-tui-tests.sh <your-openbsd-host>
```

Then attach and observe:

```sh
ssh <your-openbsd-host> 'tmux attach -t 8'
```

Use this to validate:
- rendering behavior in tmux
- keyboard input (including Enter submit)
- provider/model setup flows
- basic interactive response loop

### Phase 5: Make changes in the source repos

- `bun-openbsd` for runtime/toolchain/OpenBSD Bun changes
- `opencode-openbsd` for OpenCode/OpenTUI/OpenBSD integration changes

Re-run baseline and visible tests after changes.

### Phase 6: Promote tested OpenCode state

In `opencode-openbsd`:
- develop on `main`
- promote tested fixes to `stable/openbsd-0.1`
- tag tested snapshots (for example `openbsd-stable-YYYYMMDD`)

### Phase 7: Publish

Use `PUBLISHING-AND-PORTS-PLAN.md` for the multi-repo release/publish workflow:
- push orchestration + source repos to GitHub and SourceHut
- publish stable tags and release notes
- keep hashes and test evidence with releases

## Build vs Install: What Users Can Actually Do Today

### What works today

- Build and run Bun on OpenBSD using the documented macOS + OpenBSD workflow
- Build and run OpenCode in source mode and compiled mode on OpenBSD
- Run regression checks and interactive TUI validation

### What does not exist yet

- official OpenBSD ports entry
- `pkg_add opencode` installation path
- one-command end-user installer for OpenBSD

## Script Reference

### `scripts/test/run-openbsd-baseline.sh`

Purpose:
- generate a markdown baseline report with pass/fail checks against an OpenBSD host

Inputs:
- arg1: host alias (default: `openbsd-host`, or `OPENCODE_PORT_HOST`)
- arg2: remote workspace root (default: `/srv/opencode-port`, or `OPENCODE_PORT_REMOTE_ROOT`)
- arg3: local report directory (default: `artifacts`)

### `scripts/test/run-visible-tui-tests.sh`

Purpose:
- launch visible source/compiled TUI sessions in tmux on the OpenBSD host

Inputs:
- arg1: host alias (default: `openbsd-host`, or `OPENCODE_PORT_HOST`)
- arg2-4: tmux session/window numbers (defaults preserve the current workflow)

### `scripts/build/run-codegen.sh`

Purpose:
- run Bun codegen steps on macOS for the Bun build pipeline

Notes:
- expects `bun-source` in the workspace root
- override `WORKSPACE_ROOT` if using a different layout

## Notes on Irrelevant or Mixed Information in Existing Docs

Some docs intentionally preserve historical investigation detail. They are useful for archaeology and debugging, but not always for execution.

If you are operating the project now, prefer:
- `PORT-STATUS.md` for current status
- `OPENCODE-PORT-BUILD-GUIDE.md` for build steps
- `COMPREHENSIVE-TEST-PLAN.md` for testing
- this README for action order

Treat `PLAN.md` as a history log unless you are tracing a regression or a past patch decision.

## OpenBSD Ports / `pkg_add` Path (Short Version)

There is no separate package-name claim process.

For `pkg_add` availability, the port must be accepted into the official OpenBSD ports tree and build successfully on bulk infrastructure. See `PUBLISHING-AND-PORTS-PLAN.md` for the detailed path.
