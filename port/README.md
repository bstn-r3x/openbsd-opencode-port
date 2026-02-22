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

## Local Package (pkg_add) Goal and Standard Install Paths

Target user experience (eventual):

```sh
pkg_add opencode
opencode
```

Near-term local testing (before an official repository/mirror package exists) will use a local package file, for example:

```sh
pkg_add ./opencode-<version>.tgz
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
./port/scripts/pkg-inventory.sh

# Stage a package image tree under port/pkg-stage/image/ using /usr/local/... paths
./port/scripts/pkg-stage.sh --force
```

## Relationship to official OpenBSD ports

This `port/` workspace is for portable bundle packaging and local packaging experiments.
Official OpenBSD ports tree work (`pkg_add` from mirrors) is a separate later step.
