# Ports Tree Skeletons

This directory stores OpenBSD ports-style skeleton files (for example `misc/opencode/`) that can be copied into a real `/usr/ports` checkout.

## Purpose

- track ports metadata in git before the official port exists
- iterate on `Makefile`, `pkg/*`, and `distinfo` structure
- validate the packaging layout separately from local bundle workflows

## Current State

- `misc/opencode/` is a ports-framework bootstrap stub
- install layout and package metadata were validated locally
- a real source-distfile build strategy is still required before upstream submission
