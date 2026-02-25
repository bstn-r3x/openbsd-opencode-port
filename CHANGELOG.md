# Changelog

This file tracks current and future project changes.

Historical porting notes and deep engineering logs were moved to `HISTORY.md`.

## Unreleased

### Bun/OpenBSD Hardening
- Added Bun OpenBSD fd-path regression harness: `scripts/test/run-openbsd-bun-fdpath-smokes.sh`.
- Extended fd-path smokes to cover fd-based `Bun.write(Bun.file(...), Bun.file(...))` copy path.
- Added Bun lockfile migration smokes (npm and yarn) to the OpenBSD baseline validation script.
- Runtime-validated Bun fd-path hardening on OpenBSD after relinking a rebuilt Bun binary.

### Bun/OpenBSD Fixes (tracked in `bun-openbsd`)
- Fixed OpenBSD `poll/ppoll` dispatch to use the correct libc/OpenBSD path.
- Preserved OpenBSD `getFdPath` errno semantics instead of collapsing errors to `FileNotFound`.
- Reduced `getFdPath` workaround blast radius by replacing regular-file FD path lookups with path propagation in installer and user-facing paths (run/router/standalone compile and related install flows).
- Serialized the OpenBSD cwd-swapping `getFdPath` fallback with a process-global mutex (risk reduction while deeper cleanup is pending).

### Known Priority Work (in progress)
- Continue eliminating OpenBSD `getFdPath` fallback usage via path propagation in Bun callsites.
- Complete source-distfile/offline dependency integration for the real OpenBSD ports build path.
- Improve OpenBSD/tmux ANSI logo rendering (plaintext fallback still used in tmux-safe mode).
- Continue reducing patch debt and documenting the minimal Bun/OpenBSD patch stack.
