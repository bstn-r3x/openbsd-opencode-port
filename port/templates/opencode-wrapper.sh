#!/bin/sh
# Wrapper template for portable OpenCode bundle on OpenBSD.
# Installed as: bin/opencode

set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SELF_DIR/.." && pwd)
BIN="$ROOT_DIR/libexec/opencode/opencode-bin"

if [ ! -x "$BIN" ]; then
  echo "opencode: missing runtime binary: $BIN" >&2
  exit 1
fi

# Keep runtime relative to the extracted bundle.
exec "$BIN" "$@"
