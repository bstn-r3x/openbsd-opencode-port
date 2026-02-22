#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/run-sterile.sh [options] -- command [args...]

Run a command with isolated HOME/XDG state so local OpenCode auth/session data
(e.g. ~/.local/share/opencode/auth.json) is not visible to the process.

Options:
  --state-root PATH   Root dir for isolated HOME/XDG state (default: mktemp under /tmp)
  --keep              Keep state-root after command exits
  --quiet             Do not print state-root summary before exec
  -h, --help          Show this help
USAGE
}

die() {
  echo "run-sterile.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE_ROOT=""
KEEP=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --state-root)
      [ $# -ge 2 ] || die "missing value for --state-root"
      STATE_ROOT=$2
      shift 2
      ;;
    --keep)
      KEEP=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      die "unknown option: $1 (use -- before the command)"
      ;;
  esac
done

[ $# -gt 0 ] || die "missing command (use -- command ...)"

if [ -z "$STATE_ROOT" ]; then
  STATE_ROOT=$(mktemp -d /tmp/opencode-sterile.XXXXXX)
else
  mkdir -p "$STATE_ROOT"
fi

HOME_DIR="$STATE_ROOT/home"
XDG_CONFIG_HOME="$STATE_ROOT/xdg-config"
XDG_DATA_HOME="$STATE_ROOT/xdg-data"
XDG_STATE_HOME="$STATE_ROOT/xdg-state"
XDG_CACHE_HOME="$STATE_ROOT/xdg-cache"

mkdir -p "$HOME_DIR" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

cleanup() {
  if [ "$KEEP" -ne 1 ]; then
    rm -rf -- "$STATE_ROOT"
  fi
}
trap cleanup EXIT INT TERM

if [ "$QUIET" -ne 1 ]; then
  echo "[run-sterile] state_root=$STATE_ROOT"
  echo "[run-sterile] command=$*"
fi

TERM_VALUE=${TERM:-xterm-256color}
TMPDIR_VALUE=${TMPDIR:-/tmp}
USER_VALUE=${USER:-$(id -un 2>/dev/null || echo user)}
LOGNAME_VALUE=${LOGNAME:-$USER_VALUE}
SHELL_VALUE=${SHELL:-/bin/ksh}
PATH_VALUE=${PATH:-/bin:/usr/bin:/usr/local/bin}

exec env -i \
  HOME="$HOME_DIR" \
  XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  XDG_DATA_HOME="$XDG_DATA_HOME" \
  XDG_STATE_HOME="$XDG_STATE_HOME" \
  XDG_CACHE_HOME="$XDG_CACHE_HOME" \
  TERM="$TERM_VALUE" \
  TMPDIR="$TMPDIR_VALUE" \
  USER="$USER_VALUE" \
  LOGNAME="$LOGNAME_VALUE" \
  SHELL="$SHELL_VALUE" \
  PATH="$PATH_VALUE" \
  "$@"
