# OpenBSD Port Status (as of February 21, 2026)

## Scope
Port Bun v1.3.10 and OpenCode to OpenBSD 7.8 amd64, including `bun build --compile` for OpenCode.

## Verified in repository evidence
- Bun OpenBSD compatibility patches are present across core runtime, event loop, syscalls, spawn, installer, and bindings.
- OpenCode OpenBSD patches are present in source (`build.ts`, platform mapping, shell/clipboard/PTY/watcher handling, TUI fps change).
- OpenTUI source includes OpenBSD target support and native-target build fallback updates.
- `PLAN.md` documents successful source-mode and compiled-mode TUI rendering plus keyboard input after `isMac -> isBSD` fixes.

## Current reliability risks
- `PLAN.md` contains conflicting statuses (top summary says complete, some sections still show in-progress checklists/workarounds).
- A critical OpenTUI import resolution fix is documented as a patch to installed/cache files, not cleanly captured as a source-controlled change.
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
- Remote SSH access to `openbsd-host` is working with key-based auth.
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
2. Automated baseline checks pass on `openbsd-host` (Bun + OpenCode source + OpenCode compiled).
3. Remaining OpenBSD runtime bugs either fixed or explicitly documented with acceptance/impact.
4. Documentation reflects one canonical current state and one canonical finish plan.
