# Packaging Scripts

These scripts implement the **portable bundle packaging process** (pre-`pkg_add`), not the Bun/OpenCode source build itself.

Process stage they cover:
1. Build and verify OpenCode on OpenBSD using the normal porting workflow.
2. `stage.sh` -> assemble a relocatable staging tree under `port/stage/`.
3. `pack.sh` -> create a distributable `.tgz` and `.sha256` under `port/release/`.
4. `test.sh` -> extract and smoke-test the bundle as a user install.

Scripts:
- `stage.sh` — stage wrapper, binary, and bundle docs into `port/stage/opencode-openbsd/`
- `pack.sh` — create `opencode-openbsd-amd64-<version>.tgz` + checksum
- `test.sh` — extract bundle and run `bin/opencode --version` (optional tmux liveness smoke)

- `release-local.sh` — convenience wrapper that runs stage -> pack -> test

- `pkg-inventory.sh` — collect runtime dependency/portability inventory for the compiled binary
- `pkg-stage.sh` — stage a local package image using standard /usr/local OpenBSD install paths
