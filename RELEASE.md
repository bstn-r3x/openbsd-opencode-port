# Release Status

Canonical status summary for the OpenCode-on-OpenBSD project.

## Current State

Working today:
- OpenCode runs on OpenBSD (source mode and compiled mode)
- Portable bundle release (opencode-openbsd-amd64-*.tgz)
- Local package validation via pkg_add -D unsigned ./opencode-*.tgz

Not available yet:
- Official OpenBSD ports-tree package (pkg_add opencode from mirrors)

## Current Known Gaps (Project-Level)

- Official ports-tree port implementation is incomplete (source-distfile/build metadata still in progress)
- Bun/OpenBSD runtime patch set still has unresolved correctness risk (poll/ppoll syscall dispatch audit/fix)
- Bun/OpenBSD getFdPath workaround debt remains (error semantics + process-cwd mutation workaround)
- OpenBSD/tmux ANSI logo rendering is still imperfect (plaintext fallback used in tmux-safe mode)
- Local packaging/orchestration scripts still need metadata cleanliness cleanup (no host/path leaks in shipped bundle metadata)

## Immediate Priorities

1. Fix Bun/OpenBSD poll / ppoll dispatch and validate on OpenBSD.
2. Harden Bun/OpenBSD getFdPath behavior (preserve errors, reduce workaround blast radius).
3. Align OpenCode source build workflow with clean-clone reproducible requirements.
4. Finish local packaging script cleanup while continuing source-distfile ports work.

## Readiness Criteria (for public/maintainer releases)

- Reproducible documented build path
- Baseline validation passes on OpenBSD
- Visible tmux TUI smoke test passes
- Documentation matches current workflows and artifacts

## Source of Truth

- Current workflow docs: README.md, port/README.md, CONTRIBUTE.md
- Detailed build procedures: OPENCODE-PORT-BUILD-GUIDE.md
- Current incremental changes: CHANGELOG.md
- Historical engineering log: HISTORY.md
