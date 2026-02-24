# Ports Tree Skeletons

This directory holds OpenBSD ports-style skeletons that mirror the layout used in
`/usr/ports` (for example `misc/opencode/`).

Why this is here:
- this repo can track ports-style files even when a host does not have `/usr/ports` installed
- we still want to start and track real ports-tree metadata files (`Makefile`, `pkg/*`, `distinfo`)
- these files are intended to be copied into a real ports checkout for framework integration work

Current status:
- `misc/opencode/` is a local-bootstrap ports-framework stub (install layout + pkg metadata validated)
- it still needs a real distfile/source build strategy before upstream submission


Ports workspace setup on bstn (needed to run `make package` as a normal user):
- `/usr/ports` installed from official OpenBSD 7.8 `ports.tar.gz` (verified with `signify`)
- writable work dirs created: `/usr/ports/pobj`, `/usr/ports/distfiles`, `/usr/ports/packages`, `/usr/ports/plist`
