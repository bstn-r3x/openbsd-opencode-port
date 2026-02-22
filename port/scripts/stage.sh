#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/stage.sh [options]

Assemble a portable bundle staging tree under port/stage/.

Options:
  --bin PATH         Compiled OpenCode binary to package
                     (default: /srv/opencode-port/opencode/packages/opencode/dist/opencode-openbsd-x64/bin/opencode)
  --stage-dir PATH   Staging directory (default: <repo>/port/stage/opencode-openbsd)
  --name NAME        Bundle root directory name inside stage (default: opencode-openbsd)
  --version VERSION  Override version (default: detect from binary --version)
  --force            Remove existing stage directory before staging
  -h, --help         Show this help
USAGE
}

die() {
  echo "stage.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

DEFAULT_BIN="/srv/opencode-port/opencode/packages/opencode/dist/opencode-openbsd-x64/bin/opencode"
BIN_PATH="$DEFAULT_BIN"
BUNDLE_NAME="opencode-openbsd"
STAGE_BASE="$PORT_DIR/stage"
STAGE_DIR=""
VERSION=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bin)
      [ $# -ge 2 ] || die "missing value for --bin"
      BIN_PATH=$2
      shift 2
      ;;
    --stage-dir)
      [ $# -ge 2 ] || die "missing value for --stage-dir"
      STAGE_DIR=$2
      shift 2
      ;;
    --name)
      [ $# -ge 2 ] || die "missing value for --name"
      BUNDLE_NAME=$2
      shift 2
      ;;
    --version)
      [ $# -ge 2 ] || die "missing value for --version"
      VERSION=$2
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [ -z "$STAGE_DIR" ]; then
  STAGE_DIR="$STAGE_BASE/$BUNDLE_NAME"
fi

[ -x "$BIN_PATH" ] || die "binary is not executable: $BIN_PATH"

if [ -z "$VERSION" ]; then
  VERSION=$($BIN_PATH --version 2>/dev/null | head -1 | tr -d '\r')
fi
[ -n "$VERSION" ] || die "could not detect version"

if [ -e "$STAGE_DIR" ]; then
  if [ "$FORCE" -ne 1 ]; then
    die "stage dir exists: $STAGE_DIR (use --force)"
  fi
  rm -rf -- "$STAGE_DIR"
fi

mkdir -p "$STAGE_DIR/bin" \
         "$STAGE_DIR/libexec/opencode" \
         "$STAGE_DIR/share/doc/opencode-openbsd"

cp -p "$PORT_DIR/templates/opencode-wrapper.sh" "$STAGE_DIR/bin/opencode"
cp -p "$BIN_PATH" "$STAGE_DIR/libexec/opencode/opencode-bin"
chmod 755 "$STAGE_DIR/bin/opencode" "$STAGE_DIR/libexec/opencode/opencode-bin"

cat > "$STAGE_DIR/share/doc/opencode-openbsd/README.txt" <<DOC
OpenCode for OpenBSD (portable bundle)

Version: $VERSION
Bundle root: $BUNDLE_NAME

Run:
  ./bin/opencode

Notes:
- This is a portable pre-pkg_add bundle.
- If tmux rendering looks low-contrast, use xterm-256color and tmux-256color.
DOC

cat > "$STAGE_DIR/share/doc/opencode-openbsd/TROUBLESHOOTING.txt" <<'DOC'
Troubleshooting (portable bundle)

1. TUI appears mostly black / low contrast in tmux:
   - Use xterm-256color in the terminal emulator
   - Set tmux default-terminal to tmux-256color
   - Enable tmux truecolor overrides (Tc / RGB)
   - Reattach tmux after changing terminal settings

2. Wrapper reports missing runtime binary:
   - Ensure bundle was extracted completely and path layout is intact
   - Run via bin/opencode from inside the extracted bundle tree
DOC

cat > "$STAGE_DIR/share/doc/opencode-openbsd/BUNDLE-METADATA.txt" <<DOC
name=$BUNDLE_NAME
version=$VERSION
binary_source=$BIN_PATH
staged_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
host=$(hostname)
DOC

echo "Staged portable bundle tree: $STAGE_DIR"
echo "Version: $VERSION"
echo "Binary source: $BIN_PATH"
echo "Next: port/scripts/pack.sh --stage-dir \"$STAGE_DIR\""
