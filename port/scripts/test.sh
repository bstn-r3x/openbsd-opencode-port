#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/test.sh [options]

Smoke-test a portable bundle archive as an extracted user install.

Options:
  --archive PATH      Archive to test (default: latest .tgz in <repo>/port/release)
  --release-dir PATH  Directory to search for archives (default: <repo>/port/release)
  --work-dir PATH     Extraction temp dir (default: mktemp under /tmp)
  --tmux-smoke        Launch bundled opencode in detached tmux and verify liveness
  --tmux-session NAME tmux session name for --tmux-smoke (default: opencode-port-bundle-test)
  --keep              Keep extracted work dir (and tmux session if started)
  -h, --help          Show this help
USAGE
}

die() {
  echo "test.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

ARCHIVE_PATH=""
RELEASE_DIR="$PORT_DIR/release"
WORK_DIR=""
TMUX_SMOKE=0
TMUX_SESSION="opencode-port-bundle-test"
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --archive)
      [ $# -ge 2 ] || die "missing value for --archive"
      ARCHIVE_PATH=$2
      shift 2
      ;;
    --release-dir)
      [ $# -ge 2 ] || die "missing value for --release-dir"
      RELEASE_DIR=$2
      shift 2
      ;;
    --work-dir)
      [ $# -ge 2 ] || die "missing value for --work-dir"
      WORK_DIR=$2
      shift 2
      ;;
    --tmux-smoke)
      TMUX_SMOKE=1
      shift
      ;;
    --tmux-session)
      [ $# -ge 2 ] || die "missing value for --tmux-session"
      TMUX_SESSION=$2
      shift 2
      ;;
    --keep)
      KEEP=1
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

if [ -z "$ARCHIVE_PATH" ]; then
  ARCHIVE_PATH=$(ls -1t "$RELEASE_DIR"/*.tgz 2>/dev/null | head -1 || true)
fi
[ -n "$ARCHIVE_PATH" ] || die "no .tgz archive found (use --archive)"
[ -f "$ARCHIVE_PATH" ] || die "archive not found: $ARCHIVE_PATH"

if [ -z "$WORK_DIR" ]; then
  WORK_DIR=$(mktemp -d /tmp/opencode-port-bundle-test.XXXXXX)
else
  mkdir -p "$WORK_DIR"
fi

cleanup() {
  if [ "$TMUX_SMOKE" -eq 1 ] && [ "$KEEP" -ne 1 ]; then
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
  fi
  if [ "$KEEP" -ne 1 ]; then
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT INT TERM

tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR"

BUNDLE_DIR=""
for d in "$WORK_DIR"/*; do
  if [ -d "$d" ]; then
    BUNDLE_DIR=$d
    break
  fi
done
[ -n "$BUNDLE_DIR" ] || die "could not find extracted bundle root"

WRAPPER="$BUNDLE_DIR/bin/opencode"
[ -x "$WRAPPER" ] || die "wrapper not found: $WRAPPER"

VERSION=$($WRAPPER --version 2>/dev/null | head -1 | tr -d '\r')
[ -n "$VERSION" ] || die "wrapper did not return a version"

echo "Archive:      $ARCHIVE_PATH"
echo "Extracted to: $BUNDLE_DIR"
echo "Version:      $VERSION"

if [ "$TMUX_SMOKE" -eq 1 ]; then
  tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
  tmux new-session -d -s "$TMUX_SESSION" "cd \"$BUNDLE_DIR\" && ./bin/opencode"
  sleep 3
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null || die "tmux session did not stay alive"
  PANE_INFO=$(tmux list-panes -t "$TMUX_SESSION" -F '#{session_name}:#{window_index}.#{pane_index} pid=#{pane_pid} cmd=#{pane_current_command} alt=#{alternate_on} dead=#{pane_dead}' | head -1)
  echo "Tmux smoke:   PASS ($PANE_INFO)"
  echo "Attach:       tmux attach -t $TMUX_SESSION"
fi

if [ "$KEEP" -eq 1 ]; then
  echo "Kept work dir: $WORK_DIR"
fi
