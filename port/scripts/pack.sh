#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/pack.sh [options]

Create a portable .tgz bundle and SHA256 checksum from a staged tree.

Options:
  --stage-dir PATH    Staged bundle directory (default: <repo>/port/stage/opencode-openbsd)
  --release-dir PATH  Output directory (default: <repo>/port/release)
  --arch ARCH         Archive arch label (default: amd64)
  --version VERSION   Override version (default: detect from staged binary --version)
  --name NAME         Archive name prefix (default: opencode-openbsd)
  --force             Overwrite existing archive/checksum
  -h, --help          Show this help
USAGE
}

die() {
  echo "pack.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

STAGE_DIR="$PORT_DIR/stage/opencode-openbsd"
RELEASE_DIR="$PORT_DIR/release"
ARCH_LABEL="amd64"
NAME_PREFIX="opencode-openbsd"
VERSION=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --stage-dir)
      [ $# -ge 2 ] || die "missing value for --stage-dir"
      STAGE_DIR=$2
      shift 2
      ;;
    --release-dir)
      [ $# -ge 2 ] || die "missing value for --release-dir"
      RELEASE_DIR=$2
      shift 2
      ;;
    --arch)
      [ $# -ge 2 ] || die "missing value for --arch"
      ARCH_LABEL=$2
      shift 2
      ;;
    --version)
      [ $# -ge 2 ] || die "missing value for --version"
      VERSION=$2
      shift 2
      ;;
    --name)
      [ $# -ge 2 ] || die "missing value for --name"
      NAME_PREFIX=$2
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

[ -d "$STAGE_DIR" ] || die "stage dir not found: $STAGE_DIR"
STAGE_PARENT=$(CDPATH= cd -- "$(dirname -- "$STAGE_DIR")" && pwd)
STAGE_NAME=$(basename -- "$STAGE_DIR")
BIN_PATH="$STAGE_DIR/libexec/opencode/opencode-bin"
[ -x "$BIN_PATH" ] || die "staged binary not found: $BIN_PATH"

if [ -z "$VERSION" ]; then
  VERSION=$($BIN_PATH --version 2>/dev/null | head -1 | tr -d '\r')
fi
[ -n "$VERSION" ] || die "could not detect version"

mkdir -p "$RELEASE_DIR"
ARCHIVE_BASENAME="$NAME_PREFIX-$ARCH_LABEL-$VERSION.tgz"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_BASENAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

if [ -e "$ARCHIVE_PATH" ] || [ -e "$CHECKSUM_PATH" ]; then
  if [ "$FORCE" -ne 1 ]; then
    die "archive or checksum already exists (use --force): $ARCHIVE_BASENAME"
  fi
  rm -f -- "$ARCHIVE_PATH" "$CHECKSUM_PATH"
fi

( cd "$STAGE_PARENT" && tar -czf "$ARCHIVE_PATH" "$STAGE_NAME" )
( cd "$RELEASE_DIR" && sha256 "$ARCHIVE_BASENAME" > "$ARCHIVE_BASENAME.sha256" )

echo "Archive:  $ARCHIVE_PATH"
echo "Checksum: $CHECKSUM_PATH"
echo "Test:     port/scripts/test.sh --archive \"$ARCHIVE_PATH\""
