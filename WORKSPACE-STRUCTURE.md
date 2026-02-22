# Workspace Structure (February 21, 2026)

## Root-level policy
Keep root focused on canonical status docs and main source trees.

## Structured directories
- `scripts/build/`: build helpers and wrappers.
- `scripts/test/`: baseline and visible TUI test launchers.
- `scripts/tools/`: maintenance utilities.
- `tests/ad-hoc/`: one-off historical test files kept for reference.
- `tools/openbsd-elf/`: ELF utility source files.
- `archives/source-tarballs/`: source tarballs retained for reference.
- `backups/<timestamp>/`: structured backup snapshots.

## Compatibility
Root paths used in existing docs are preserved via symlinks:
- `run-openbsd-baseline.sh`
- `run-visible-tui-tests.sh`
- `run-codegen.sh`
- `zig-wrapper.sh`
- `zig2-wrapper.sh`
- `strip_debug_sections.py`
- `patch_machinecontext.py`
- `add-openbsd-note.c`
- `fix-openbsd-elf.c`
