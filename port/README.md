# Local Packaging Workspace (`port/`)

`port/` contains maintainer workflows for:
- portable release bundles (`opencode-openbsd-amd64-*.tgz`)
- local OpenBSD package validation (`pkg_add -D unsigned ./opencode-*.tgz`)

It is not the official OpenBSD ports tree.

## Terms

- `<openbsd-opencode-port-repo>`: local checkout of this repo on an OpenBSD host
- `<opencode-repo>`: local checkout of `opencode-openbsd`
- `<tmpdir>`: writable temp dir with enough free space for Bun compile

## Which `.tgz` File Is Which?

- `opencode-openbsd-amd64-<version>.tgz`: portable bundle (end-user extract-and-run)
- `opencode-<pkg-version>.tgz`: local OpenBSD package test artifact (`pkg_add`)
- GitHub `Source code (tar.gz)`: source only, not runnable

## Portable Bundle (Maintainer Workflow)

From repo root:

```sh
./port/scripts/release-local.sh --force --tmux-smoke
```

Equivalent explicit steps:

```sh
./port/scripts/stage.sh --force
./port/scripts/pack.sh --force
./port/scripts/test.sh --tmux-smoke
```

Common overrides:
- `./port/scripts/stage.sh --bin /path/to/opencode --force`
- `./port/scripts/test.sh --archive /path/to/opencode-openbsd-amd64-<version>.tgz --tmux-smoke`
- `./port/scripts/test.sh --archive /path/to/opencode-openbsd-amd64-<version>.tgz --tmux-smoke --allow-host-state`

## Portable Bundle (End-User Workflow)

```sh
sha256 -C opencode-openbsd-amd64-<version>.tgz.sha256 || sha256 opencode-openbsd-amd64-<version>.tgz
mkdir -p ~/.local
tar -xzf opencode-openbsd-amd64-<version>.tgz -C ~/.local
~/.local/opencode-openbsd/bin/opencode
```

## Security Note (Interactive TUI Tests)

OpenCode may reuse host-local auth/session state from XDG paths (for example `~/.local/share/opencode/auth.json`).

For reproducible/safe tmux tests, use sterile state:
- `./port/scripts/run-sterile.sh -- <command>`
- `./port/scripts/test.sh --tmux-smoke` (sterile by default)

On shared hosts, verify permissions before testing:

```sh
stat -f "%Sp %N" ~/.local/share/opencode ~/.local/share/opencode/auth.json
chmod 700 ~/.local/share/opencode
chmod 600 ~/.local/share/opencode/auth.json
```

## Local OpenBSD Package Workflow (`pkg_add` Test Artifact)

Target install paths in the staged package image:
- `/usr/local/bin/opencode`
- `/usr/local/libexec/opencode/opencode-bin`
- `/usr/local/share/doc/opencode/README.txt`
- `/usr/local/share/doc/opencode/TROUBLESHOOTING.txt`

Build and inspect:

```sh
./port/scripts/pkg-inventory.sh --fail-on-private-path
./port/scripts/pkg-stage.sh --force
./port/scripts/pkg-pack.sh --inventory-gate --force
```

Install test (on OpenBSD test host/VM):

```sh
doas pkg_delete opencode 2>/dev/null || true
doas pkg_add -D unsigned /tmp/opencode-<pkg-version>.tgz
opencode --version
```

Visible tmux test (recommended sterile mode):

```sh
TERM=xterm-256color tmux -u new-session -s opencode-pkg-visible \
  'ST=/tmp/opencode-sterile; rm -rf "$ST"; mkdir -p "$ST/home" "$ST/xdg-config" "$ST/xdg-data" "$ST/xdg-state" "$ST/xdg-cache"; unset OPENAI_API_KEY OPENAI_ACCESS_TOKEN OPENAI_API_BASE OPENAI_BASE_URL ANTHROPIC_API_KEY OPENCODE_API_KEY CODEX_API_KEY; env HOME="$ST/home" XDG_CONFIG_HOME="$ST/xdg-config" XDG_DATA_HOME="$ST/xdg-data" XDG_STATE_HOME="$ST/xdg-state" XDG_CACHE_HOME="$ST/xdg-cache" PATH=/bin:/usr/bin:/usr/local/bin TERM=xterm-256color /usr/local/bin/opencode'
```

## Source-Distfile Prep (Maintainer Prototype)

For source-distfile port experiments (Option 1):

```sh
./port/scripts/source-vendor-prep.sh \
  --work-dir <tmpdir>/opencode-source-prep \
  --archive-dir <tmpdir>/opencode-source-prep-artifacts \
  --force
```

This validates a clean-clone filtered Bun install/build workflow and can produce source + filtered dependency archives for ports experiments.

## Official Ports Status

This workspace is for local packaging and validation.
Official `pkg_add opencode` requires a completed and accepted OpenBSD port.
