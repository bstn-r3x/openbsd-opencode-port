# Release Status

Canonical status summary for the OpenCode-on-OpenBSD project.

## Current State

Working today:
- OpenCode runs on OpenBSD (source mode and compiled mode)
- Portable bundle release (`opencode-openbsd-amd64-*.tgz`)
- Local package validation via `pkg_add -D unsigned ./opencode-*.tgz`

Not available yet:
- Official OpenBSD ports-tree package (`pkg_add opencode` from mirrors)

## Current Known Gaps (Project-Level)

- Official ports-tree port implementation is incomplete (distfile/build metadata still in progress)
- OpenBSD/tmux ANSI logo rendering is still imperfect (plaintext fallback used in tmux-safe mode)
- Some OpenBSD runtime/workaround debt remains in Bun/OpenCode forks and should be minimized/upstreamed

## Readiness Criteria (for public/maintainer releases)

- Reproducible documented build path
- Baseline validation passes on OpenBSD
- Visible tmux TUI smoke test passes
- Documentation matches current workflows and artifacts

## Source of Truth

- Current workflow docs: `README.md`, `port/README.md`, `CONTRIBUTE.md`
- Detailed build procedures: `OPENCODE-PORT-BUILD-GUIDE.md`
- Historical engineering log: `CHANGELOG.md`
