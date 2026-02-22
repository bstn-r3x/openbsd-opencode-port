#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/run-sterile.sh [options] -- command [args...]

Run a command with isolated HOME/XDG state so local OpenCode auth/session data
(e.g. ~/.local/share/opencode/auth.json) is not visible to the process.

This wrapper intentionally preserves terminal/tmux/locale environment so TUI
rendering behaves like a normal interactive session.

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

# Keep interactive terminal/tmux/locale env for rendering fidelity, but move all
# OpenCode state to an isolated XDG root and clear common provider credential envs.
PATH=${PATH:-/bin:/usr/bin:/usr/local/bin}
TMPDIR=${TMPDIR:-/tmp}
TERM=${TERM:-xterm-256color}
export PATH TMPDIR TERM
export HOME="$HOME_DIR"
export OPENCODE_TEST_HOME="$HOME_DIR"
export XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME

# Unset common provider/auth environment variables to reduce accidental auth reuse
# even if the host shell has them exported.
for name in \
  OPENAI_API_KEY OPENAI_ACCESS_TOKEN OPENAI_ORG_ID OPENAI_BASE_URL OPENAI_API_BASE \
  AZURE_OPENAI_API_KEY AZURE_OPENAI_ENDPOINT \
  ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN \
  GEMINI_API_KEY GOOGLE_API_KEY GOOGLE_GENERATIVE_AI_API_KEY \
  OPENROUTER_API_KEY CEREBRAS_API_KEY XAI_API_KEY MISTRAL_API_KEY \
  TOGETHER_API_KEY PERPLEXITY_API_KEY DEEPSEEK_API_KEY GROQ_API_KEY \
  FIREWORKS_API_KEY COHERE_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
  OPENCODE_API_KEY OPENCODE_TOKEN CODEX_API_KEY
 do
  unset "$name" 2>/dev/null || true
 done

exec "$@"
