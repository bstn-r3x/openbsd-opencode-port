#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/release-local.sh [options]

Convenience wrapper for the portable bundle workflow:
  1) stage.sh
  2) pack.sh
  3) test.sh

Options:
  --bin PATH          Forward to stage.sh --bin
  --stage-dir PATH    Forward to stage.sh/pack.sh --stage-dir
  --release-dir PATH  Forward to pack.sh/test.sh --release-dir
  --name NAME         Forward to stage.sh --name and pack.sh --name
  --arch ARCH         Forward to pack.sh --arch (default: amd64)
  --version VERSION   Forward to stage.sh/pack.sh --version
  --force             Pass --force to stage.sh and pack.sh
  --skip-test         Skip test.sh
  --tmux-smoke        Enable test.sh --tmux-smoke
  --keep-test-workdir Pass --keep to test.sh
  -h, --help          Show this help
USAGE
}

die() {
  echo "release-local.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

BIN_PATH=""
STAGE_DIR=""
RELEASE_DIR=""
NAME=""
ARCH=""
VERSION=""
FORCE=0
SKIP_TEST=0
TMUX_SMOKE=0
KEEP_TEST_WORKDIR=0

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
    --release-dir)
      [ $# -ge 2 ] || die "missing value for --release-dir"
      RELEASE_DIR=$2
      shift 2
      ;;
    --name)
      [ $# -ge 2 ] || die "missing value for --name"
      NAME=$2
      shift 2
      ;;
    --arch)
      [ $# -ge 2 ] || die "missing value for --arch"
      ARCH=$2
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
    --skip-test)
      SKIP_TEST=1
      shift
      ;;
    --tmux-smoke)
      TMUX_SMOKE=1
      shift
      ;;
    --keep-test-workdir)
      KEEP_TEST_WORKDIR=1
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

printf '%s\n' '[1/3] stage.sh'
set -- "$SCRIPT_DIR/stage.sh"
[ -n "$BIN_PATH" ] && set -- "$@" --bin "$BIN_PATH"
[ -n "$STAGE_DIR" ] && set -- "$@" --stage-dir "$STAGE_DIR"
[ -n "$NAME" ] && set -- "$@" --name "$NAME"
[ -n "$VERSION" ] && set -- "$@" --version "$VERSION"
[ "$FORCE" -eq 1 ] && set -- "$@" --force
"$@"

printf '%s\n' '[2/3] pack.sh'
set -- "$SCRIPT_DIR/pack.sh"
[ -n "$STAGE_DIR" ] && set -- "$@" --stage-dir "$STAGE_DIR"
[ -n "$RELEASE_DIR" ] && set -- "$@" --release-dir "$RELEASE_DIR"
[ -n "$ARCH" ] && set -- "$@" --arch "$ARCH"
[ -n "$NAME" ] && set -- "$@" --name "$NAME"
[ -n "$VERSION" ] && set -- "$@" --version "$VERSION"
[ "$FORCE" -eq 1 ] && set -- "$@" --force
"$@"

if [ "$SKIP_TEST" -eq 1 ]; then
  printf '%s\n' '[3/3] test.sh (skipped)'
  exit 0
fi

printf '%s\n' '[3/3] test.sh'
set -- "$SCRIPT_DIR/test.sh"
[ -n "$RELEASE_DIR" ] && set -- "$@" --release-dir "$RELEASE_DIR"
[ "$TMUX_SMOKE" -eq 1 ] && set -- "$@" --tmux-smoke
[ "$KEEP_TEST_WORKDIR" -eq 1 ] && set -- "$@" --keep
"$@"
