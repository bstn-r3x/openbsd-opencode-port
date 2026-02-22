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

## Start Here (Important Links)

- **[Build Guide: `OPENCODE-PORT-BUILD-GUIDE.md`](OPENCODE-PORT-BUILD-GUIDE.md)**
- **[Current Status: `PORT-STATUS.md`](PORT-STATUS.md)**
- **[Contributing Guide: `CONTRIBUTE.md`](CONTRIBUTE.md)**
- **[Main Engineering History + Consolidated Finish Plan: `PLAN.md`](PLAN.md)**
- **[Placeholder Mapping (sanitized host/path names): `PLACEHOLDERS.md`](PLACEHOLDERS.md)**
- **[Enter-submit bug deep dive (historical fix record): `ENTER-SUBMIT-FIX-PLAN.md`](ENTER-SUBMIT-FIX-PLAN.md)**

## Related Repositories

This project is split into three repos:

1. `openbsd-opencode-port` (this repo)
   - orchestration docs, scripts, runbooks, publish workflow
2. `bun-openbsd`
   - Bun source snapshot/fork with OpenBSD porting changes
3. `opencode-openbsd`
   - OpenCode source snapshot/fork with OpenBSD-specific fixes and tested tag/branch

## Who This Is For

### End users

This project is **not yet** a normal end-user install path.

- There is no official OpenBSD package in ports yet
- `pkg_add` does not work because the port is not accepted upstream
- Current usage is a porter/developer workflow (source + build/test)

### Porters / maintainers

Start here and follow the sequence below. The docs are intentionally ordered so you can operate without reading the entire project history first.

## Canonical Reading Order

1. `README.md` (this file)
2. `PLACEHOLDERS.md`
3. `PORT-STATUS.md`
4. `OPENCODE-PORT-BUILD-GUIDE.md`
5. `CONTRIBUTE.md`
6. `PLAN.md` (history + deeper details)

## Operator Sequence (Practical Order of Actions)

### 1. Clone and orient

1. Clone all three repositories (`openbsd-opencode-port`, `bun-openbsd`, `opencode-openbsd`).
2. Read `PLACEHOLDERS.md` and map placeholder names to your real host/path names.
3. Read `PORT-STATUS.md` to confirm current reality before using older notes.

### 2. Prepare environment

1. Confirm SSH access to your OpenBSD host.
2. Confirm `tmux` is installed on OpenBSD.
3. Review `OPENCODE-PORT-BUILD-GUIDE.md` prerequisites and expected layout.
4. Place the Bun/OpenCode source repos in the paths expected by your workflow (or use script overrides where available).

### 3. Validate before changing code

Run the automated baseline:

```sh
./scripts/test/run-openbsd-baseline.sh <your-openbsd-host>
```

This checks SSH connectivity, Bun smoke tests, OpenCode source liveness, and compiled binary presence/version (if present).

### 4. Run visible interactive TUI validation

Launch source-mode and compiled-mode TUI sessions in tmux on the OpenBSD host:

```sh
./scripts/test/run-visible-tui-tests.sh <your-openbsd-host>
```

Then attach and inspect:

```sh
ssh <your-openbsd-host> 'tmux attach -t 8'
```

Use this for rendering, input handling (including Enter submit), provider/model setup, and general interaction checks.

### 5. Make changes in source repos

- `bun-openbsd` for Bun runtime/toolchain/OpenBSD compatibility changes
- `opencode-openbsd` for OpenCode/OpenTUI/OpenBSD integration changes

Re-run baseline and visible TUI validation after changes.

### 6. Promote tested state and publish

Use `CONTRIBUTE.md` for branch strategy and push/publish workflow to GitHub and SourceHut.

## Repo Contents (and Non-Contents)

Included here:
- markdown docs/runbooks
- `scripts/build/*` build helpers
- `scripts/test/*` baseline and visible TUI helpers
- `scripts/tools/*` maintenance utilities

Not included here:
- full Bun/OpenCode source trees
- `node_modules`, build outputs, caches
- compiled binaries/toolchains
- secrets, auth/session data, SSH keys
- private runtime dumps

## Notes on Documentation Scope

This repo keeps a small set of operational docs. Some older planning/reference material is intentionally **not** kept in the published repo.

Example: the earlier publishing/ports planning draft is now treated as a local reference file, while `CONTRIBUTE.md` provides the public contributor workflow.

## OpenBSD Ports / `pkg_add` (Short Version)

There is no separate package-name claim system.

For `pkg_add` availability, the port must be accepted into the official OpenBSD ports tree and build successfully on bulk infrastructure.
