# Publishing, Branching, and OpenBSD Ports Plan

## Current state (Feb 21, 2026)
- Local workspace renamed to: `<MAC_WORKSPACE>/opencode-port`.
- Remote workspace organized at: `/srv/opencode-port`.
- Working backup created on openbsd-host:
  - `/srv/opencode-port/backups/20260221-213425-working/`
- `bun-source` is a git repo (local + openbsd-host).
- `opencode` tree is now a git repo on openbsd-host:
  - path: `/srv/opencode-port/opencode`
  - branch: `main`
  - baseline commit: `7b078bc` (`OpenBSD known-good baseline (2026-02-21)`)
  - note: local `opencode-src` is still non-git and can be aligned in the next step.

## 1. Publishing Plan (GitHub + SourceHut)

### 1.1 Repository model
Use **three repos** to keep maintenance clean:
1. `openbsd-opencode-port` (orchestration repo)
   - Docs, build scripts, test scripts, release notes, patch sets, CI recipes.
2. `bun-openbsd` (fork/branch of Bun)
   - OpenBSD Bun port commits.
3. `opencode-openbsd` (fork/branch of OpenCode)
   - OpenBSD OpenCode commits (TUI/PTY/watcher/renderer fixes).

### 1.2 Prep before first push
1. Initialize git history for `opencode` working tree from current known-good state.
2. Ensure `.gitignore` excludes heavy/generated artifacts:
   - `node_modules/`, `dist/`, `.zig-cache/`, `build/`, local logs, temporary binaries.
3. Export and commit patch provenance:
   - Bun diff from `bun-source` (`git diff` + curated commits).
   - OpenCode working diff as initial commits.
4. Add release docs:
   - tested host info,
   - exact build commands,
   - known issues and mitigations,
   - verification matrix.

### 1.3 Push workflow
1. Create remotes for GitHub and SourceHut in each repo.
2. Push the same commit graph to both for redundancy.
3. Tag tested milestones (`v0.1-openbsd-stable`, etc).

## 2. Branch Strategy (stable vs dev)

### 2.1 Branch naming
- `main` -> active development.
- `stable/openbsd-0.1` -> frozen branch used by others.
- tags -> immutable tested points (`openbsd-stable-YYYYMMDD`).

### 2.2 Promotion flow
1. Develop on `main`.
2. Run full baseline + interactive validation.
3. Fast-forward or cherry-pick into `stable/openbsd-0.1` only tested fixes.
4. Tag the stable head.
5. Publish release notes referencing tag + artifact hashes.

### 2.3 Access model
- Others consume `stable/*` branches and tags.
- Maintainers work on `main` and feature branches.

## 3. OpenBSD pkg_add / ports path

### 3.1 "Claiming" a package name
There is no separate external "name claim" system for OpenBSD official packages.
- Name is effectively established by the port (`PKGNAME`/stem) when accepted in ports.
- Must avoid collisions with existing package stems in the ports tree.

### 3.2 What must happen for `pkg_add` availability
1. Port must be accepted into OpenBSD ports tree.
2. It must build on official bulk infrastructure.
3. Resulting package appears on mirrors and is installable via `pkg_add`.

### 3.3 Practical steps to become a real OpenBSD port
1. Create candidate port directory (likely category such as `devel/opencode`).
2. Add proper port files (`Makefile`, `distinfo`, `pkg/PLIST`, `pkg/DESCR`, etc).
3. Ensure fully reproducible build in ports environment (no ad-hoc network fetch during build phases).
4. Run porter checks (`make makesum`, `make fake`, `make package`, dependency and plist checks).
5. Test install/remove/upgrade via `pkg_add` and `pkg_delete`.
6. Submit diff to `ports@openbsd.org` for review.
7. Iterate until accepted and committed.

### 3.4 Major blocker to track now
OpenCode currently depends on Bun; if Bun itself is not accepted in ports, OpenCode port acceptance is significantly harder.
- Option A: first upstream/port Bun.
- Option B: make OpenCode build/run in a ports-acceptable way without custom Bun runtime.

## 4. Immediate execution sequence (recommended)
1. Create git repo for current OpenCode working tree and commit known-good baseline. (DONE on openbsd-host: `7b078bc`)
2. Create `stable/openbsd-0.1` branch and tag tested state. (DONE on openbsd-host: branch `stable/openbsd-0.1`, tag `openbsd-stable-20260221`, both at `7b078bc`)
3. Create/push orchestration repo to GitHub and SourceHut.
4. Push Bun + OpenCode repos to both remotes.
5. Start a dedicated `ports/` subdir in orchestration repo with draft OpenBSD port files.

