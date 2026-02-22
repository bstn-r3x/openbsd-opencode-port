#!/bin/sh
# zig2-wrapper.sh - Wrapper around zig2 that patches produced binaries
# with OpenBSD note section before they're executed.
#
# This intercepts the zig build process by:
# 1. Running zig2 build which compiles the build runner
# 2. zig2 will fail trying to execute it (InvalidExe)
# 3. We patch the build runner in the cache
# 4. We then invoke the build runner directly with the right args

OPENBSD_WORKSPACE_ROOT="${OPENBSD_WORKSPACE_ROOT:-/srv/opencode-port}"
ZIG2="${OPENBSD_WORKSPACE_ROOT}/oven-zig/zig2"
PATCHER="${OPENBSD_WORKSPACE_ROOT}/add-openbsd-note"
WORKDIR="${OPENBSD_WORKSPACE_ROOT}/oven-zig"

# Run zig2 build, capturing the error about the build runner path
OUTPUT=$("$ZIG2" "$@" 2>&1)
RC=$?

if [ $RC -eq 0 ]; then
    echo "$OUTPUT"
    exit 0
fi

# Check if it's a build runner spawn failure
BUILD_RUNNER=$(echo "$OUTPUT" | grep "failed to spawn build runner" | sed 's/.*failed to spawn build runner //' | sed 's/:.*//')

if [ -z "$BUILD_RUNNER" ]; then
    echo "$OUTPUT"
    exit $RC
fi

echo "Intercepted: build runner at $BUILD_RUNNER"
echo "Patching with OpenBSD note..."

# Patch the build runner
"$PATCHER" "$BUILD_RUNNER"
if [ $? -ne 0 ]; then
    echo "Failed to patch build runner"
    exit 1
fi

# Now extract the arguments zig2 would have passed to the build runner
# From the error message, the format is:
# .zig-cache/o/<hash>/build <zig-binary> lib <workdir> .zig-cache <global-cache> --seed <seed> -Z<hash> [user args]

# Re-run zig2 - it should find the cached (now patched) build runner
echo "Re-running zig2 build..."
"$ZIG2" "$@" 2>&1
