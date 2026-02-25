# Packaging Scripts

Scripts in this directory support two maintainer workflows:
- portable bundle packaging (`stage.sh`, `pack.sh`, `test.sh`, `release-local.sh`)
- local OpenBSD package validation (`pkg-inventory.sh`, `pkg-stage.sh`, `pkg-pack.sh`)

Important:
- `test.sh --tmux-smoke` is sterile by default (does not reuse host auth/session state)
- `pkg-pack.sh --inventory-gate` is the recommended local package build path
- `pkg-sanitize-binary.sh` is a legacy fallback for older binaries (use source-level sanitization first)

Source-distfile prep:
- `source-vendor-prep.sh` prepares a clean-clone OpenCode workspace with filtered Bun deps for ports experiments
- it emits a source tarball plus a filtered dependency tarball containing `node_modules` and all workspace `packages/*/node_modules` symlink dirs
- requires `bun`, `node`, `node-gyp`, `python3`, `gmake`, and a spacious `TMPDIR`
