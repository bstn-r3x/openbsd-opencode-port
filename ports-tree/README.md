# Ports Tree Skeletons

This directory holds OpenBSD ports-style skeletons that mirror the layout used in
`/usr/ports` (for example `misc/opencode/`).

Why this is here:
- `bstn` currently does not have a local `/usr/ports` tree installed
- we still want to start and track real ports-tree metadata files (`Makefile`, `pkg/*`, `distinfo`)
- these files are intended to be copied into a real ports checkout for framework integration work

Current status:
- `misc/opencode/` is an initial skeleton with install-layout tracking and TODOs
- it is intentionally marked `BROKEN` until the ports framework build/install path is implemented
