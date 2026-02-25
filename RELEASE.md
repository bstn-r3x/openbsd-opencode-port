# Release Status

Canonical status summary for the OpenCode-on-OpenBSD project.

## Current State

Working today:
- OpenCode runs on OpenBSD (source mode and compiled mode)
- Portable bundle release (opencode-openbsd-amd64-*.tgz)
- Local package validation via `pkg_add -D unsigned ./opencode-*.tgz`

Not available yet:
- Official OpenBSD ports-tree package (`pkg_add opencode` from mirrors)

## Current Known Gaps (Project-Level)

- Official ports-tree port implementation is incomplete (source-distfile/build metadata still in progress)
- Bun/OpenBSD `getFdPath` still relies on an OpenBSD directory-FD fallback that swaps process cwd (`fchdir + getcwd + restore`)
- OpenBSD/tmux ANSI logo rendering is still imperfect (plaintext fallback used in tmux-safe mode)
- Source-distfile/offline dependency workflow for the final ports build path is not fully wired into `/usr/ports/misc/opencode`

## Immediate Priorities

1. Keep reducing Bun/OpenBSD `getFdPath` fallback usage via path propagation (avoid reverse-resolving regular file FD paths).
2. Keep using the trampoline-based Bun relink helper (`scripts/build/relink-bun-openbsd.sh`) instead of symbol-rewriting `bun-zig.o`.
3. Add/maintain Bun OpenBSD fd-path regression smokes in the maintainer validation workflow.
4. Continue source-distfile ports work (offline dependency provisioning + ports-framework build/install path).
5. Finish remaining runtime/polish issues (OpenBSD tmux ANSI logo rendering, patch debt reduction).

## Bun/OpenBSD fd-path Hardening Strategy (Current Plan)

Goal: make OpenBSD behavior robust without relying on process-global cwd mutation except as a last-resort directory-FD fallback.

### Phase 1: Safety + Regression Coverage (done/in progress)
- Preserve OpenBSD `getFdPath` errno semantics (no blanket `FileNotFound` collapse).
- Avoid `getFdPath()` on known regular-file FD callsites in installer and user-facing paths.
- Serialize the OpenBSD cwd-swapping fallback with a process-global mutex (risk reduction).
- Maintain command-level regression smokes (`run`, lockfile migrations, standalone compile, fd-based `Bun.write`).

### Phase 2: Preferred Architecture (next)
- Continue replacing reverse FD-path lookups with explicit path propagation.
- Introduce small helpers/patterns for “open file + keep path” flows.
- Treat `getFdPath()` on OpenBSD as directory-FD-only / last resort in code review.

### Phase 3: Core Cleanup (longer-term)
- Document/enforce OpenBSD `getFdPath` contract more explicitly.
- Investigate any viable non-cwd-mutating directory-FD path strategy on OpenBSD (if one exists).
- If none exists, keep shrinking fallback usage until it is rare and well-contained.

## Readiness Criteria (for public/maintainer releases)

- Reproducible documented build path
- Baseline validation passes on OpenBSD
- Bun OpenBSD fd-path smokes pass on OpenBSD
- Bun relink (if rebuilt) succeeds with `scripts/build/relink-bun-openbsd.sh`
- Visible tmux TUI smoke test passes
- Documentation matches current workflows and artifacts

## Source of Truth

- Current workflow docs: `README.md`, `port/README.md`, `CONTRIBUTE.md`
- Detailed build procedures: `OPENCODE-PORT-BUILD-GUIDE.md`
- Current incremental changes: `CHANGELOG.md`
- Historical engineering log: `HISTORY.md`
