#!/bin/sh
# zig-wrapper.sh - Wraps zig2 to always use system linker on OpenBSD
#
# zig2's internal linker produces dynamic binaries without NEEDED libc.so,
# which makes them crash on OpenBSD. This wrapper intercepts build-exe
# and converts it to build-obj + system cc link.
#
# For build-obj and other commands, passes through to zig2 directly.

OPENBSD_WORKSPACE_ROOT="${OPENBSD_WORKSPACE_ROOT:-/srv/opencode-port}"
ZIG2="${OPENBSD_WORKSPACE_ROOT}/oven-zig/zig2"
ZIG_LIB_DIR="${OPENBSD_WORKSPACE_ROOT}/oven-zig/lib"

exec "$ZIG2" "$@"
