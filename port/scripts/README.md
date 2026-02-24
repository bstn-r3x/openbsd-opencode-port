# Packaging Scripts

These scripts cover two packaging tracks after OpenCode is already built on OpenBSD:
- portable bundle packaging (`port/stage/`, `port/release/`)
- local OpenBSD package (`pkg_add`) staging/packing experiments (`port/pkg-stage/`, `port/pkg-report/`)

Security note (important for tests):
- OpenCode may use host-local auth/session state from `~/.local/share/opencode/` and XDG state dirs.
- For reproducible/safe tmux validation, use sterile state (`run-sterile.sh`) unless you intentionally want your personal account/session.

Process stage they cover:
1. Build and verify OpenCode on OpenBSD using the normal porting workflow.
2. Portable bundle: `stage.sh` -> `pack.sh` -> `test.sh` (or `release-local.sh`).
3. Local package groundwork: `pkg-inventory.sh` -> `pkg-stage.sh` -> `pkg-pack.sh`.
4. Install-test local package with `pkg_add -D unsigned` on a test VM.
5. Run visible TUI checks in tmux using sterile state.

Scripts:
- `stage.sh` — stage wrapper, binary, and bundle docs into `port/stage/opencode-openbsd/`
- `pack.sh` — create `opencode-openbsd-amd64-<version>.tgz` + checksum
- `test.sh` — extract bundle and run `bin/opencode --version` (optional tmux liveness smoke; tmux smoke is sterile by default)
- `release-local.sh` — convenience wrapper that runs stage -> pack -> test
- `pkg-inventory.sh` — collect runtime dependency/portability inventory for the compiled binary (supports gating via `--forbid-pattern` and `--fail-on-private-path`)
- `pkg-stage.sh` — stage a local package image using standard /usr/local OpenBSD install paths
- `pkg-pack.sh` — build a real local OpenBSD package (`.tgz`) from the staged package image
- `run-sterile.sh` — run OpenCode (or any command) with isolated HOME/XDG state so local auth/session data is not used
