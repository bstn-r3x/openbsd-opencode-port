# Portable Bundle Workspace (`port/`)

This directory is the local packaging workspace for producing a portable OpenBSD release tarball before an official OpenBSD `pkg_add` port exists.

## Goal

Produce a relocatable `.tgz` bundle that a user can:
1. download
2. verify (`sha256`)
3. extract anywhere
4. run via `bin/opencode`

## Planned layout (generated under `port/stage/`)

```text
port/stage/opencode-openbsd/
  bin/
    opencode              # wrapper script (stable entrypoint)
  libexec/
    opencode/
      opencode-bin        # compiled OpenCode binary
      ...                 # runtime files if needed
  share/
    doc/opencode-openbsd/
      README.txt
      TROUBLESHOOTING.txt
```

The release tarball and checksum files are generated under `port/release/`.

## What belongs in git

Tracked:
- `port/README.md`
- `port/scripts/*` (packaging helpers)
- `port/templates/*` (wrapper and text templates)
- `port/stage/.gitignore`
- `port/release/.gitignore`

Not tracked:
- built bundles (`.tgz`)
- checksums/signatures generated per release
- staged binaries/runtime payloads

## Expected end-user workflow (portable bundle)

```sh
# user downloads release files
sha256 -C opencode-openbsd-amd64-<version>.tgz.sha256
mkdir -p ~/.local
tar -xzf opencode-openbsd-amd64-<version>.tgz -C ~/.local
~/.local/opencode-openbsd/bin/opencode
```

## Packaging Commands (maintainer workflow)

From the repo root:

```sh
./port/scripts/release-local.sh --force --tmux-smoke

# Equivalent explicit steps:
./port/scripts/stage.sh --force
./port/scripts/pack.sh --force
./port/scripts/test.sh --tmux-smoke
```

Common overrides:
- `./port/scripts/stage.sh --bin /path/to/opencode --force`
- `./port/scripts/pack.sh --stage-dir /custom/stage --release-dir /custom/release --force`
- `./port/scripts/test.sh --archive /path/to/opencode-openbsd-amd64-<version>.tgz --tmux-smoke`
- `./port/scripts/test.sh --archive /path/to/opencode-openbsd-amd64-<version>.tgz --tmux-smoke --allow-host-state` (only if you intentionally want host auth/session state)

## Security Note: Host Auth State During TUI Tests

OpenCode may automatically use host-local auth/session state from standard XDG paths, including files under:
- `~/.local/share/opencode/` (notably `auth.json`)
- `~/.local/state/opencode/`
- `~/.cache/opencode/`

This is runtime behavior on the host and is **not** caused by the package payload itself.

For reproducible and safe tmux validation (especially on shared/test hosts), run OpenCode with isolated `HOME/XDG_*` state using `./port/scripts/run-sterile.sh` (build host) or an equivalent wrapper that preserves tmux/terminal env (test VM).

On shared hosts, also verify auth state file permissions before interactive testing:

```sh
stat -f "%Sp %N" ~/.local/share/opencode ~/.local/share/opencode/auth.json
chmod 700 ~/.local/share/opencode
chmod 600 ~/.local/share/opencode/auth.json
```

## Local Package (pkg_add) Goal and Standard Install Paths

Target user experience (eventual):

```sh
pkg_add opencode
opencode
```

Near-term local testing (before an official repository/mirror package exists) uses a local package file and an unsigned-package override, for example:

```sh
doas pkg_add -D unsigned ./opencode-<pkg-version>.tgz
opencode
```

Standard OpenBSD install paths planned for the local package image:
- `/usr/local/bin/opencode` (wrapper command users run)
- `/usr/local/libexec/opencode/opencode-bin` (compiled binary)
- `/usr/local/share/doc/opencode/README.txt`
- `/usr/local/share/doc/opencode/TROUBLESHOOTING.txt`

User runtime data is not packaged into system directories; it remains in the user's home directory (for example `~/.opencode/`).

### Local package groundwork commands (maintainer)

```sh
# Inspect runtime dependencies / portability signals
./port/scripts/pkg-inventory.sh --fail-on-private-path

# Stage a package image tree under port/pkg-stage/image/ using /usr/local/... paths
./port/scripts/pkg-stage.sh --force

# Build a real local OpenBSD package for pkg_add under port/pkg-stage/packages/
./port/scripts/pkg-pack.sh --force
```

### Local package test flow (exact maintainer flow)

Tested on OpenBSD 7.8 with a locally built package file (example package name shown; your `<pkg-version>` may differ because `pkg_create` package versions are sanitized from the app `--version` string).

```sh
# On the build host (example: bstn)
cd /srv/opencode-port/publish/repos/openbsd-opencode-port
./port/scripts/pkg-stage.sh --force
./port/scripts/pkg-pack.sh --force
ls -lh port/pkg-stage/packages/*.tgz
sha256 port/pkg-stage/packages/*.tgz
```

Optional visible compiled-binary tmux check on the build host (sterile, recommended):

```sh
# Leaves host ~/.local/share/opencode/auth.json and other XDG state unused
TERM=xterm-256color tmux -u new-session -s opencode-build-visible \
  'cd /srv/opencode-port/publish/repos/openbsd-opencode-port && ./port/scripts/run-sterile.sh -- /srv/opencode-port/opencode/packages/opencode/dist/opencode-openbsd-x64/bin/opencode'
# Detach with Ctrl-b d after confirming rendering/input
```

Copy the package to the test VM (use any method that preserves bytes, e.g. `scp` or SSH relay):

```sh
# Example destination on test VM
/tmp/opencode-<pkg-version>.tgz
```

```sh
# On the test VM (example: openbsd-vm)
tmux kill-session -t opencode-pkg-visible 2>/dev/null || true
pkill -f '/usr/local/bin/opencode|opencode-bin' 2>/dev/null || true

doas pkg_delete opencode 2>/dev/null || true

doas pkg_add -D unsigned /tmp/opencode-<pkg-version>.tgz
opencode --version
which opencode
ls -l \
  /usr/local/bin/opencode \
  /usr/local/libexec/opencode/opencode-bin \
  /usr/local/share/doc/opencode/README.txt \
  /usr/local/share/doc/opencode/TROUBLESHOOTING.txt

# Visible tmux TUI test (sterile HOME/XDG state so host auth/session data is not reused)
TERM=xterm-256color tmux -u new-session -s opencode-pkg-visible \
  'ST=/tmp/opencode-sterile; rm -rf "$ST"; mkdir -p "$ST/home" "$ST/xdg-config" "$ST/xdg-data" "$ST/xdg-state" "$ST/xdg-cache"; unset OPENAI_API_KEY OPENAI_ACCESS_TOKEN OPENAI_API_BASE OPENAI_BASE_URL ANTHROPIC_API_KEY OPENCODE_API_KEY CODEX_API_KEY; env HOME="$ST/home" XDG_CONFIG_HOME="$ST/xdg-config" XDG_DATA_HOME="$ST/xdg-data" XDG_STATE_HOME="$ST/xdg-state" XDG_CACHE_HOME="$ST/xdg-cache" PATH=/bin:/usr/bin:/usr/local/bin TERM=xterm-256color /usr/local/bin/opencode'
# Detach with Ctrl-b d after confirming rendering/input

# Uninstall / reinstall validation
doas pkg_delete opencode
doas pkg_add -D unsigned /tmp/opencode-<pkg-version>.tgz
opencode --version
```

Notes:
- `pkg_add` rejects unsigned local packages by default; use `-D unsigned` for this local test workflow.
- `pkg_delete` uses the installed package name/stem (`opencode`).
- The package file name may differ from the app version string because `pkg_create` enforces package-name formatting.
- If you intentionally want to test your logged-in provider account/session behavior, do not use the sterile wrappers.

## Relationship to official OpenBSD ports

This `port/` workspace is for portable bundle packaging and local packaging experiments.
Official OpenBSD ports tree work (`pkg_add` from mirrors) is a separate later step.
