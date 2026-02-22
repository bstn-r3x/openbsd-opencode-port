# Finish Plan (starting February 21, 2026)

## Phase 0: Re-establish execution path
Goal: regain remote execution loop and capture a baseline report.

Status: COMPLETED on February 21, 2026 (`artifacts/openbsd-baseline-20260221-191735.md`).

Tasks:
1. Confirm `openbsd-host` network reachability from host where this workspace runs.
2. Run `./run-openbsd-baseline.sh`.
3. Store generated report under `artifacts/` and treat it as baseline truth.

Exit criteria:
- One successful baseline report generated in this repo with pass/fail per check.

## Phase 1: Documentation normalization
Goal: make status and process unambiguous.

Status: IN PROGRESS (core docs aligned; historical `PLAN.md` still contains mixed legacy status text).

Tasks:
1. Keep `PORT-STATUS.md` as single source of current state.
2. Trim `PLAN.md` to historical log + pointer to current status.
3. Update `OPENCODE-PORT-BUILD-GUIDE.md` checklists to checked/unchecked based on latest baseline report.

Exit criteria:
- No contradictory project status statements across docs.

## Phase 2: Reproducibility hardening
Goal: remove off-tree/manual patches and make rebuild deterministic.

Tasks:
1. Move any required runtime fix from cache/node_modules edits into source-controlled patches.
2. Ensure OpenTUI OpenBSD loading behavior is implemented at source level (not post-install edits).
3. Script the full build pipeline (cross-compile, strip, transfer, relink) with clear inputs/outputs.

Exit criteria:
- Fresh checkout + documented commands produce a working Bun/OpenCode on `openbsd-host` without ad-hoc edits.

## Phase 3: Runtime stabilization
Goal: close high-value remaining bugs.

Tasks:
1. OpenCode prompt Enter-submit path on OpenBSD tmux (`P0`):
   - Source-mode root cause and fix are complete (stale prompt state vs live textarea content).
   - Source-mode and compiled-mode user verification are complete in visible tmux.
   - Remaining work: keep durable regression coverage in source tree/tests.
2. Fix or bound `execSync/spawnSync` hang on OpenBSD.
3. Implement proper OpenBSD installer symlink behavior (remove workaround dependency).
4. Re-check idle CPU target with a repeatable measurement method.
5. Diagnose and fix OpenCode TUI ANSI/header rendering corruption above the prompt in tmux on OpenBSD.
   - Mitigation implemented in source and rebuilt compiled binary: OpenBSD+tmux safe logo rendering path and ANSI-style removal from session exit header strings.
   - Remaining work: close visual acceptance with live tmux confirmation in both panes.

Exit criteria:
- Known-bug table reduced to only accepted, low-impact items with explicit rationale.

## Phase 4: Release readiness
Goal: finalize handoff quality.

Status: IN PROGRESS (comprehensive run executed; compiled CPU regression blocks closure).

Tasks:
1. Run full validation matrix (Bun smoke + OpenCode source mode + compiled mode).
2. Capture results in a dated release report.
3. Document exact commands for rebuild and verify.

Exit criteria:
- "Done" report with reproducible commands and passing baseline checks.
