#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-${OPENCODE_PORT_HOST:-openbsd-host}}"
REMOTE_ROOT="${2:-${OPENCODE_PORT_REMOTE_ROOT:-/srv/opencode-port}}"
REPORT_DIR="${3:-artifacts}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-120}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_PATH="${REPORT_DIR}/openbsd-bun-fdpath-smokes-${STAMP}.md"
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
  local rc=0
  if output="$(run_with_timeout "${CHECK_TIMEOUT}" "$@" 2>&1)"; then
    echo "Status: PASS"
    echo
    echo '```text'
    echo "${output}"
    echo '```'
    return 0
  else
    rc=$?
  fi

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
  echo "# OpenBSD Bun fd-path Smoke Report"
  echo
  echo "- Generated: $(date)"
  echo "- Host alias: \`${HOST}\`"
  echo "- Remote root: \`${REMOTE_ROOT}\`"
  echo "- Timeout per check: ${CHECK_TIMEOUT}s"

  run_check "SSH connectivity" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "echo connected"

  run_check "Bun version" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "${REMOTE_ROOT}/bun --version"

  run_check "Bun run file-path smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "set -e; d=\$(mktemp -d /tmp/bun-run-file-smoke.XXXXXX); mkdir -p \"\$d/sub\"; printf 'console.log(\\\"run-file-ok\\\")\\n' > \"\$d/sub/hello.js\"; cd \"\$d\"; ${REMOTE_ROOT}/bun run ./sub/hello.js"

  run_check "Bun npm lockfile migration smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "set -e; d=\$(mktemp -d /tmp/bun-npm-migrate-smoke.XXXXXX); cd \"\$d\"; printf '{\"name\":\"smoke\",\"version\":\"1.0.0\"}\\n' > package.json; printf '{\"name\":\"smoke\",\"version\":\"1.0.0\",\"lockfileVersion\":3,\"requires\":true,\"packages\":{\"\":{\"name\":\"smoke\",\"version\":\"1.0.0\"}}}\\n' > package-lock.json; ${REMOTE_ROOT}/bun install >/tmp/bun-npm-migrate-smoke.log 2>&1; echo npm-migrate-ok:\$d"

  run_check "Bun yarn lockfile migration smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "set -e; d=\$(mktemp -d /tmp/bun-yarn-migrate-smoke.XXXXXX); cd \"\$d\"; printf '{\"name\":\"smoke\",\"version\":\"1.0.0\"}\\n' > package.json; printf '# yarn lockfile v1\\n' > yarn.lock; ${REMOTE_ROOT}/bun install >/tmp/bun-yarn-migrate-smoke.log 2>&1; echo yarn-migrate-ok:\$d"

  run_check "Bun standalone compile smoke" \
    ssh "${SSH_OPTS[@]}" "${HOST}" "set -e; d=\$(mktemp -d /tmp/bun-compile-smoke.XXXXXX); cd \"\$d\"; printf 'console.log(\\\"compile-smoke-ok\\\")\\n' > hello.js; ${REMOTE_ROOT}/bun build --compile ./hello.js --outfile ./hello >/tmp/bun-compile-smoke.log 2>&1; ./hello"

  echo
  echo "## Summary"
  echo "- Failed checks: ${FAIL_COUNT}"
} > "${REPORT_PATH}"

echo "Bun fd-path smoke report written to ${REPORT_PATH}"
if [ "${FAIL_COUNT}" -gt 0 ]; then
  exit 1
fi
