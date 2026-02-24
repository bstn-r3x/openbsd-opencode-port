# Release Status and Readiness

This file is the canonical public summary for:
- current OpenBSD port status
- verified evidence and risks
- release readiness criteria
- near-term release/finish plan

Use this file for current-state and release decisions. Use `CHANGELOG.md` for detailed engineering history.

## Current OpenBSD Port Status (as of February 21, 2026)

## Scope
Port Bun v1.3.10 and OpenCode to OpenBSD 7.8 amd64, including `bun build --compile` for OpenCode.

## Verified in repository evidence
- Bun OpenBSD compatibility patches are present across core runtime, event loop, syscalls, spawn, installer, and bindings.
- OpenCode OpenBSD patches are present in source (`build.ts`, platform mapping, shell/clipboard/PTY/watcher handling, TUI fps change).
- OpenTUI source includes OpenBSD target support and native-target build fallback updates.
- `CHANGELOG.md` documents successful source-mode and compiled-mode TUI rendering plus keyboard input after `isMac -> isBSD` fixes.

## Current reliability risks
- `CHANGELOG.md` contains historical mixed-era status notes and should be treated as engineering history rather than the current release summary.
- OpenTUI import portability fix is now captured as a source-controlled OpenCode build patch (`packages/opencode/script/build.ts`) that rewrites the installed `@opentui/core` loader with an OpenBSD relative fallback; local rebuild + relocated binary smoke validation completed on `<openbsd-host>`, cross-machine validation still pending.
- Enter-submit fix has been applied and user-verified in both source and compiled tmux sessions.
- Some runtime issues remain open and marked non-blocking:
  - `child_process.execSync/spawnSync` intermittent hang.
  - `bun install` symlink behavior on OpenBSD still relying on workaround.
  - CPU behavior needs a stable benchmark target and repeatable measurement.
  - OpenCode TUI visual artifact in tmux/OpenBSD has mitigation patches applied in source and rebuilt compiled binary (safe logo rendering + ANSI-style removal in session header); final visual acceptance is still pending operator confirmation.

## Enter-submit status (February 21, 2026)
- Physical Enter key produces raw CR byte (`0x0d`) on stdin.
- OpenCode key event parsing sees Enter as `name="return"` and `sequence="\r"`.
- Root cause from phase tracing: prompt submit path used stale `store.prompt.input` while textarea `input.plainText` already had text at Enter time.
- Fix applied: submit now sources from live textarea content first (`input.plainText`), synchronizes store, then submits.
- Supporting guard retained: global command key handling skips `input_submit` so Enter is handled by focused prompt path.
- User validation in visible tmux panes confirmed prompt submission now works in source and compiled modes (model replies observed).
- Remaining Enter work: maintain regression coverage so stale-state submit behavior does not regress.

## Live baseline executed today (February 21, 2026)
- Remote SSH access to `<openbsd-host>` is working with key-based auth.
- Automated baseline report generated:
  - `artifacts/openbsd-baseline-20260221-191735.md`
- Current automated checks in that report:
  - PASS: SSH connectivity, system info.
  - PASS: Bun version/eval/spawn/fetch (localhost + external HTTPS).
  - PASS: `bun install` smoke.
  - PASS: OpenCode source help command.
  - PASS: OpenCode TUI liveness smoke (non-interactive, 4s).
  - PASS: OpenCode `dev.log` error-pattern scan (`no-error-patterns`).
  - PASS: OpenCode compiled binary version check.

## Comprehensive test execution (February 21, 2026)
- Full matrix run report:
  - `artifacts/comprehensive-test-report-20260221-1558.md`
- Key outcomes:
  - Source-mode typing/navigation/Enter submit path is functional in live tmux verification after fix.
  - CLI/API coverage passing.
  - Build/compile smoke checks passing.
  - **Compiled-mode CPU regression remains** (observed sustained ~100% CPU during soak).

## Completion criteria for this project
1. Fully reproducible source-controlled build path (no manual cache/node_modules edits).
2. Automated baseline checks pass on `<openbsd-host>` (Bun + OpenCode source + OpenCode compiled).
3. Remaining OpenBSD runtime bugs either fixed or explicitly documented with acceptance/impact.
4. Documentation reflects a canonical release summary (`RELEASE.md`) and accurate operational guidance in the build/contribution docs.

## Release Readiness Plan

### Phase 0: Re-establish execution path
- Goal: regain remote execution loop and capture a baseline report.
- Status: Completed on February 21, 2026 (`artifacts/openbsd-baseline-20260221-191735.md`).
- Tasks:
  1. Confirm OpenBSD host network reachability from the orchestration host.
  2. Run the baseline script.
  3. Store the generated report in `artifacts/` and use it as baseline truth.
- Exit criteria: one successful baseline report with pass/fail per check.

### Phase 1: Documentation normalization
- Goal: make status and process unambiguous.
- Status: Partially complete; core docs aligned, `CHANGELOG.md` remains a historical log with mixed-era content.
- Tasks:
  1. Keep `RELEASE.md` as the current-state summary.
  2. Keep `CHANGELOG.md` as history + deeper technical notes.
  3. Keep `OPENCODE-PORT-BUILD-GUIDE.md` and `CONTRIBUTE.md` aligned with current commands and release workflow.
- Exit criteria: no contradictory operational guidance in the active docs.

### Phase 2: Reproducibility hardening
- Goal: remove off-tree/manual patches and make rebuild deterministic.
- Update (February 22, 2026): OpenTUI loader portability fallback has been moved into a source-controlled OpenCode build patch and validated on `<openbsd-host>` (local rebuild + relocated compiled binary launch). Fresh-machine validation is the next step.
- Tasks:
  1. Move any required runtime fix from cache or `node_modules` edits into source-controlled patches.
  2. Ensure OpenTUI OpenBSD loading behavior is captured in source-controlled changes.
  3. Script the build pipeline (cross-compile, strip, transfer, relink) with explicit inputs/outputs.
- Exit criteria: fresh checkout + documented commands reproduce a working Bun/OpenCode build on OpenBSD without ad-hoc edits.

### Phase 3: Runtime stabilization
- Goal: close high-value remaining bugs.
- Tasks:
  1. Retain regression coverage for the Enter-submit TUI fix.
  2. Fix or bound `execSync/spawnSync` intermittent hangs on OpenBSD.
  3. Replace `bun install` workaround dependencies with a proper OpenBSD-compatible behavior.
  4. Re-check idle CPU target using a repeatable measurement method.
  5. Finalize visual acceptance for tmux/OpenBSD TUI rendering artifacts (mitigations are already implemented).
- Exit criteria: remaining known bugs are low-impact and explicitly documented with rationale/mitigation.

### Phase 4: Release readiness
- Goal: finalize handoff quality and stable publication process.
- Tasks:
  1. Run full validation matrix (Bun smoke + OpenCode source mode + compiled mode).
  2. Capture a dated release report.
  3. Keep rebuild and verification commands exact and current.
- Exit criteria: reproducible commands + passing baseline checks + documented stable state.
