#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-${OPENCODE_PORT_HOST:-openbsd-host}}"
REMOTE_ROOT="${2:-${OPENCODE_PORT_REMOTE_ROOT:-/srv/opencode-port}}"
REPORT_DIR="${3:-artifacts}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-45}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_PATH="${REPORT_DIR}/openbsd-baseline-${STAMP}.md"
SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ConnectionAttempts=1
  -o NumberOfPasswordPrompts=0
  -o StrictHostKeyChecking=accept-new
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=2
)
FAIL_COUNT=0

mkdir -p "${REPORT_DIR}"

section() {
  local title="$1"
  echo
  echo "## ${title}"
}

check() {
  local name="$1"
  shift

  section "${name}"
  local output
  if output="$(run_with_timeout "${CHECK_TIMEOUT}" "$@" 2>&1)"; then
    echo "Status: PASS"
    echo
    echo '```text'
    echo "${output}"
    echo '```'
    return 0
  fi

  local rc=$?
  echo "Status: FAIL (exit ${rc})"
  echo
  echo '```text'
  echo "${output}"
  echo '```'
  return 1
}

run_with_timeout() {
  local timeout_secs="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_secs}" "$@"
    return $?
  fi

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_secs}" "$@"
    return $?
  fi

  python3 - "$timeout_secs" "$@" <<'PY'
import subprocess
import sys

timeout = int(sys.argv[1])
cmd = sys.argv[2:]

try:
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
        check=False,
    )
    sys.stdout.write(proc.stdout or "")
    sys.exit(proc.returncode)
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        if isinstance(exc.stdout, bytes):
            sys.stdout.write(exc.stdout.decode("utf-8", "replace"))
        else:
            sys.stdout.write(exc.stdout)
    print(f"TIMEOUT after {timeout}s")
    sys.exit(124)
PY
}

run_check() {
  if ! check "$@"; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

{
  echo "# OpenBSD Baseline Report"
  echo
  echo "- Generated: $(date)"
  echo "- Host alias: \`${HOST}\`"
  echo "- Remote root: \`${REMOTE_ROOT}\`"

  run_check "SSH connectivity" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "echo connected"

  run_check "Remote system info" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "uname -a; date; uptime || true"

  run_check "Bun version" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "${REMOTE_ROOT}/bun --version"

  run_check "Bun eval smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "${REMOTE_ROOT}/bun -e 'console.log(1+1)'"

  run_check "Bun spawn smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "${REMOTE_ROOT}/bun -e '(async()=>{const p=Bun.spawn([\"echo\",\"spawn-ok\"],{stdout:\"pipe\"});const out=await new Response(p.stdout).text();await p.exited;console.log(out.trim())})()'"

  run_check "Bun fetch localhost smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "${REMOTE_ROOT}/bun -e '(async()=>{const s=Bun.serve({port:0,fetch(){return new Response(\"ok\")}});const r=await fetch(\"http://127.0.0.1:\"+s.port);console.log(await r.text());s.stop(true)})()'"

  run_check "Bun fetch external HTTPS smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "${REMOTE_ROOT}/bun -e '(async()=>{const r=await fetch(\"https://httpbin.org/get\");console.log(r.status);const j=await r.json();console.log(j.url)})()'"

  run_check "Bun install smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "set -e; d=\$(mktemp -d /tmp/bun-install-smoke.XXXXXX); cd \"\$d\"; printf '{\"name\":\"smoke\",\"version\":\"1.0.0\",\"dependencies\":{\"left-pad\":\"1.3.0\"}}\n' > package.json; ${REMOTE_ROOT}/bun install >/tmp/bun-install-smoke.log 2>&1; test -d node_modules/left-pad && echo install-ok:\$d"

  run_check "OpenCode source help" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "cd ${REMOTE_ROOT}/opencode/packages/opencode && ${REMOTE_ROOT}/bun run --conditions=browser src/index.ts --help | head -n 40"

  run_check "OpenCode TUI liveness (non-interactive, 4s)" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "set -e; cd ${REMOTE_ROOT}/opencode/packages/opencode; ${REMOTE_ROOT}/bun run --conditions=browser src/index.ts >/tmp/opencode-tui-smoke.log 2>&1 & pid=\$!; sleep 4; if kill -0 \"\$pid\" 2>/dev/null; then echo tui-alive; kill \"\$pid\"; wait \"\$pid\" 2>/dev/null || true; else echo tui-exited-early; tail -n 120 /tmp/opencode-tui-smoke.log; exit 1; fi"

  run_check "OpenCode dev.log error-pattern scan" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "LOG=\$HOME/.local/share/opencode/log/dev.log; if [ ! -f \"\$LOG\" ]; then echo log-missing:\$LOG; exit 0; fi; if grep -nE '\\\\b(ERROR|FATAL|panic|segfault)\\\\b' \"\$LOG\" >/tmp/opencode-log-errors.txt; then echo error-patterns-found; tail -n 20 /tmp/opencode-log-errors.txt; exit 1; fi; echo no-error-patterns"

  run_check "OpenCode compiled version (if present)" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "if [ -x ${REMOTE_ROOT}/opencode-bin ]; then ${REMOTE_ROOT}/opencode-bin --version; else echo 'opencode-bin not present'; fi"

  echo
  echo "## Summary"
  echo "- Failed checks: ${FAIL_COUNT}"
} > "${REPORT_PATH}"

echo "Baseline report written to ${REPORT_PATH}"
if [ "${FAIL_COUNT}" -gt 0 ]; then
  exit 1
fi
