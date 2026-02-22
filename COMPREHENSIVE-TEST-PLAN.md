# Comprehensive Test Plan: OpenCode Port on OpenBSD (`openbsd-host`)

Date: February 21, 2026
Target host: `openbsd-host` (`OpenBSD 7.8 amd64`)
Primary binaries:
- `/srv/opencode-port/bun`
- `/srv/opencode-port/opencode-bin`
- `/srv/opencode-port/opencode/packages/opencode` (source mode)

## 1. Test goals
1. Verify Bun runtime correctness for OpenCode-critical functionality on OpenBSD.
2. Verify OpenCode works in both source mode and compiled mode.
3. Verify stability under interactive TUI usage and repeated command execution.
4. Verify build/install paths are reproducible and regression-safe.

## 2. Visibility and operator workflow (tmux)
Use tmux session `8` for live visibility:
- Window `8`: OpenCode source mode TUI
- Window `9`: OpenCode compiled binary TUI

Current pane mapping (latest run):
- `8:8.0` source TUI
- `8:9.0` compiled TUI

Optional observer command:
```sh
ssh openbsd-host 'tmux attach -t 8'
```

## 3. Pre-test hygiene
Before each full run:
1. Kill stale OpenCode/Bun processes from previous runs.
2. Ensure windows `8` and `9` are clean shells.
3. Confirm logs path exists: `~/.local/share/opencode/log/dev.log`.
4. Run baseline script:
```sh
./run-openbsd-baseline.sh
```

## 4. Test matrix

### A. Baseline automation (non-interactive)
Command:
```sh
./run-openbsd-baseline.sh
```
Must pass:
- SSH, Bun version/eval/spawn
- fetch localhost + HTTPS
- bun install smoke
- OpenCode source help
- OpenCode TUI liveness smoke
- log error-pattern scan
- compiled binary version

### B. Interactive TUI functional tests (source and compiled)
Run simultaneously in tmux windows `8` and `9`.

Manual checks in both modes:
1. Launch and stable idle for 2-3 minutes.
2. Keyboard input appears in prompt.
3. Basic command palette/model switch shortcuts respond.
4. Submit a short prompt with plain Enter and confirm streaming response path.
5. Cancel/interrupt behavior works.
6. Exit cleanly and relaunch successfully.
7. Visual integrity check: no corrupted ANSI/logo/header artifacts above the input area.

Pass criteria:
- No freeze, panic, or premature exit.
- Input/output path works.
- Process remains responsive.
- Enter key in focused prompt must submit text (not only insert/retain text).

## 4.1 Current state snapshot (February 21, 2026)
- Enter-submit root cause identified: submit path read stale `store.prompt.input` while textarea `input.plainText` already had user text.
- Fix applied in prompt submit path: use `input.plainText` first, sync store, then run submit/trim/history flow.
- Live tmux validation in source mode: PASS (user typed text, pressed Enter, prompt submitted).
- Live tmux validation in compiled mode: PASS (user confirmed input submit and model reply).
- ANSI/logo/header corruption above prompt now has mitigation in source and rebuilt compiled binary (safe tmux/OpenBSD logo render path + session header ANSI style removal); final visual acceptance is pending operator confirmation.

### C. CLI/API coverage
Commands to verify:
```sh
ssh openbsd-host 'cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/opencode-bin --help'
ssh openbsd-host 'cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/opencode-bin models'
ssh openbsd-host 'cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/opencode-bin stats'
ssh openbsd-host 'cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/opencode-bin debug config'
```
Pass criteria:
- Exit code 0
- No critical error logs

### D. Runtime bug regression checks
Focus areas:
1. `child_process.execSync/spawnSync` hang reproduction and frequency.
2. `bun install` symlink behavior and postinstall script behavior.
3. OpenTUI loading path behavior (no manual cache patch dependency).

Pass criteria:
- Known issues either fixed or reproducible with clear repro + logs.

### E. Performance and stability
Checks:
1. Idle CPU samples for source and compiled TUI.
2. 30-minute soak with periodic interaction.
3. Worker/process cleanup on exit (no zombie/stuck tasks).

Pass criteria:
- No sustained pathological CPU spin.
- No process leaks after exit.

### F. Build and reproducibility
Checks:
1. Re-run documented Bun/OpenCode build path.
2. Re-run compile target generation.
3. Verify resulting binaries pass sections A-C.

Pass criteria:
- Fresh rebuild produces runnable artifacts with same behavior.

## 5. Evidence capture requirements
For each phase:
1. Save command transcript/log snippets.
2. Record exit codes.
3. Record any failures with exact command + timestamp.
4. Update status docs:
   - `PORT-STATUS.md`
   - `OPENCODE-PORT-BUILD-GUIDE.md`
   - `PLAN.md` pointer note (if latest report path changes)

## 6. Release gate
Port is release-ready only if:
1. Baseline automation fully passes.
2. Interactive TUI checks pass in source and compiled modes.
3. Remaining known bugs are either fixed or explicitly accepted with mitigation.
4. Rebuild from documented steps reproduces working artifacts.

## Appendix: Launch commands used for interactive validation
Source mode:
```sh
ssh -t openbsd-host 'cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/bun run --conditions=browser src/index.ts'
```

Compiled mode:
```sh
ssh -t openbsd-host 'cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/opencode-bin'
```
