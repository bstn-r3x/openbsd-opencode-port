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

## Relationship to official OpenBSD ports

This `port/` workspace is for portable bundle packaging and local packaging experiments.
Official OpenBSD ports tree work (`pkg_add` from mirrors) is a separate later step.
