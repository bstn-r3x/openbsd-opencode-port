# Enter Submit Fix Plan (OpenCode TUI on OpenBSD `openbsd-host`)

Date: February 21, 2026
Priority: `P0` (core interaction path)

## Problem statement
In the OpenCode TUI main prompt, plain Enter failed to submit user input in real tmux interaction on `openbsd-host`.

## Verified facts
1. Raw stdin receives Enter as carriage return (`0x0d`, `\r`).
2. Key parsing produces `name="return"` and `sequence="\r"`.
3. Prompt accepts typed text and other shortcuts.
4. User observed prompt text entry and shortcuts, but Enter did not submit.

## Root cause (confirmed)
`submit()` was using `store.prompt.input`, which could be stale at Enter press time, while the live textarea already had text in `input.plainText`. This triggered an early empty-input return path.

## Deep investigation plan

### Phase A: Handler-flow trace (minimal, short-lived)
1. Add scoped trace points with timestamps and key payload in:
   - raw stdin listener
   - global key handlers (command/dialog/session/app)
   - prompt `useKeyboard` submit handler
   - textarea `onKeyDown` and textarea `onSubmit`
   - start/end and early-return paths inside `submit()`
2. Capture one canonical run:
   - type fixed token + Enter in visible tmux pane
   - collect ordered trace log
3. Derive exact path:
   - where Enter is consumed or where submit exits.

Exit criteria:
- Single trace file showing deterministic Enter path from stdin to final outcome.

Status: COMPLETED.
- Enter reached prompt submit handler as `name="return"` with `sequence="\r"`.
- Trace showed `input.plainText` non-empty while `store.prompt.input` was empty.

### Phase B: Minimal fix from trace
1. Apply smallest fix at the true failure point (not layered fallbacks).
2. Validate in source mode and compiled mode in tmux.
3. Ensure no regressions for:
   - autocomplete selection Enter behavior
   - dialog Enter behavior
   - command palette keybindings

Exit criteria:
- Enter submits prompt reliably in both source and compiled modes.

Status: COMPLETED.
- Implemented fix in prompt submit path to read `input.plainText` first, sync store, and use live input for trim/history.
- Source-mode tmux validation: PASS (user confirmed Enter submits).
- Compiled-mode tmux validation: PASS (user confirmed submit and model reply).

### Phase C: Regression coverage
1. Add automated regression test/harness:
   - integration path or deterministic key-event harness proving Enter submit.
2. Add manual smoke script for tmux-visible confirmation.
3. Remove all temporary tracing code.

Exit criteria:
- Reproducible test that fails before fix and passes after.

Status: IN PROGRESS.
- Added focused stale-input selection test in local source tree: `opencode-src/packages/opencode/test/prompt-submit-input.test.ts`.
- Remaining work: run this test in the remote build tree and keep it in the standard regression suite.

## Acceptance criteria
1. In pane `8:8.0`, typing text and pressing Enter sends prompt every time. (Source mode: PASS)
2. Prompt text clears after submit and response path starts.
3. No stale/hanging background processes after repeated runs.
4. No side effects on `ctrl+p`, dialogs, or slash/autocomplete flows.
