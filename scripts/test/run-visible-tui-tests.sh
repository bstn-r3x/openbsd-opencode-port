#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-${OPENCODE_PORT_HOST:-openbsd-host}}"
SESSION="${2:-8}"
SRC_WIN="${3:-8}"
BIN_WIN="${4:-9}"
REMOTE_ROOT="${OPENCODE_PORT_REMOTE_ROOT:-/srv/opencode-port}"
ROOT="${REMOTE_ROOT}/opencode/packages/opencode"
BUN="${REMOTE_ROOT}/bun"
BIN="${REMOTE_ROOT}/opencode-bin"
SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ConnectionAttempts=1
  -o NumberOfPasswordPrompts=0
  -o StrictHostKeyChecking=accept-new
)

ssh "${SSH_OPTS[@]}" "${HOST}" "
  set -e
  tmux start-server 2>/dev/null || true
  tmux set-option -g destroy-unattached off 2>/dev/null || true

  if ! tmux has-session -t '${SESSION}' 2>/dev/null; then
    tmux new-session -d -s '${SESSION}' -n 'bootstrap'
  fi

  tmux kill-window -t '${SESSION}:${SRC_WIN}' 2>/dev/null || true
  tmux kill-window -t '${SESSION}:${BIN_WIN}' 2>/dev/null || true
  tmux new-window -t '${SESSION}:${SRC_WIN}' -n '${SRC_WIN}'
  tmux new-window -t '${SESSION}:${BIN_WIN}' -n '${BIN_WIN}'

  tmux send-keys -t '${SESSION}:${SRC_WIN}.0' \"cd ${ROOT} && ${BUN} run --conditions=browser src/index.ts\" C-m
  tmux send-keys -t '${SESSION}:${BIN_WIN}.0' \"cd ${ROOT} && ${BIN}\" C-m

  tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{pane_tty} cmd=#{pane_current_command}'
"

echo "Visible TUI tests started on ${HOST} in tmux session ${SESSION}."
echo "Attach with: ssh ${HOST} 'tmux attach -t ${SESSION}'"
