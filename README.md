# OpenCode on OpenBSD (perosnal project)

This repository is my project for running the OpenCode on OpenBSD.
I started it for experiment with Claude and now continue with Codex. 
It seems to work fine so far and I will try to continue to polish it when I have some spare time.

It contains:
- release and status docs
- maintainer scripts for bundle and local package validation
- ports-tree skeleton files for the future OpenBSD port

It does not contain full Bun/OpenCode source history or official OpenBSD packages.

## Status

- Portable OpenBSD bundle (`.tgz`): available via GitHub Releases
- Local OpenBSD package (`pkg_add -D unsigned ./...tgz`): validated for maintainer testing
- Official OpenBSD `pkg_add opencode`: not available (port not upstreamed)

## For Users (Run OpenCode on OpenBSD Today)

Download the portable release assets from GitHub Releases:
- `opencode-openbsd-amd64-<version>.tgz`
- `opencode-openbsd-amd64-<version>.tgz.sha256`

Do not use GitHub's default `Source code (tar.gz)` asset for running OpenCode.

Quick start:

```sh
sha256 -C opencode-openbsd-amd64-<version>.tgz.sha256 || sha256 opencode-openbsd-amd64-<version>.tgz
mkdir -p ~/.local
tar -xzf opencode-openbsd-amd64-<version>.tgz -C ~/.local
~/.local/opencode-openbsd/bin/opencode
```

## For Maintainers / Porters

Start here:
1. `RELEASE.md` (current status + blockers)
2. `port/README.md` (portable bundle + local package workflows)
3. `OPENCODE-PORT-BUILD-GUIDE.md` (detailed multi-host build guide)
4. `CONTRIBUTE.md` (branching, validation, publishing)
5. `CHANGELOG.md` (engineering history)

## Repositories

- `openbsd-opencode-port` (this repo): docs, scripts, packaging/ports experiments
- `opencode-openbsd`: OpenCode fork/snapshot with OpenBSD changes
- `bun-openbsd`: Bun fork/snapshot with OpenBSD changes

## Notes

- `port/` is a local packaging workspace (portable bundle + local `pkg_add` validation).
- `ports-tree/` contains tracked ports-style skeleton files to copy into a real `/usr/ports` checkout.
- Official `pkg_add opencode` requires an accepted OpenBSD port and mirror-built packages.
