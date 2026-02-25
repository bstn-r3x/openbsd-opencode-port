# Ports Tree Skeletons

This directory stores OpenBSD ports-style skeleton files (for example `misc/opencode/`) that can be copied into a real `/usr/ports` checkout.

## Purpose

- track ports metadata in git before the official port exists
- iterate on `Makefile`, `pkg/*`, and `distinfo` structure
- validate the packaging layout separately from local bundle workflows

## Current State

- `misc/opencode/` is a ports-framework prototype source-distfile port (local maintainer distfiles)
- install layout and package metadata were validated locally
- a local source-distfile prototype build path now works in `/usr/ports`, but published distfiles + final metadata are still required before upstream submission
- remaining build blockers include Bun build dependencies, offline dependency provisioning, and source completeness for clean-clone builds
