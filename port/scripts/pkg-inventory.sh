#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/pkg-inventory.sh [options]

Collect runtime dependency and portability signals from a compiled opencode binary.

Options:
  --bin PATH              Compiled binary path
                          (default: /srv/opencode-port/opencode/packages/opencode/dist/opencode-openbsd-x64/bin/opencode)
  --output PATH           Output report file (default: <repo>/port/pkg-report/runtime-inventory.txt)
  --append                Append to existing report instead of overwrite
  --forbid-pattern REGEX  Fail the command if strings output matches REGEX (repeatable)
  --fail-on-private-path  Convenience gate for maintainer host path leaks (/srv/opencode-port)
  -h, --help              Show this help
USAGE
}

die() {
  echo "pkg-inventory.sh: $*" >&2
  exit 1
}

append_forbid_pattern() {
  if [ -z "${FORBID_PATTERNS:-}" ]; then
    FORBID_PATTERNS=$1
  else
    FORBID_PATTERNS="$FORBID_PATTERNS
$1"
  fi
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

BIN_PATH="/srv/opencode-port/opencode/packages/opencode/dist/opencode-openbsd-x64/bin/opencode"
OUTPUT_PATH="$PORT_DIR/pkg-report/runtime-inventory.txt"
APPEND=0
FORBID_PATTERNS=""
FAIL_ON_PRIVATE_PATH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bin)
      [ $# -ge 2 ] || die "missing value for --bin"
      BIN_PATH=$2
      shift 2
      ;;
    --output)
      [ $# -ge 2 ] || die "missing value for --output"
      OUTPUT_PATH=$2
      shift 2
      ;;
    --append)
      APPEND=1
      shift
      ;;
    --forbid-pattern)
      [ $# -ge 2 ] || die "missing value for --forbid-pattern"
      append_forbid_pattern "$2"
      shift 2
      ;;
    --fail-on-private-path)
      FAIL_ON_PRIVATE_PATH=1
      append_forbid_pattern '/srv/opencode-port'
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

[ -x "$BIN_PATH" ] || die "binary is not executable: $BIN_PATH"
mkdir -p "$(dirname -- "$OUTPUT_PATH")"

STRINGS_CACHE=$(mktemp /tmp/opencode-pkg-inventory.XXXXXX)
cleanup() {
  rm -f -- "$STRINGS_CACHE"
}
trap cleanup EXIT INT TERM

if ! strings -a "$BIN_PATH" > "$STRINGS_CACHE" 2>/dev/null; then
  : > "$STRINGS_CACHE"
fi

if [ "$APPEND" -eq 1 ]; then
  {
    echo '== OpenCode Runtime Inventory =='
    echo "collected_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "host=$(hostname)"
    echo "binary=$BIN_PATH"
  } >> "$OUTPUT_PATH"
else
  cat > "$OUTPUT_PATH" <<EOF_REPORT
== OpenCode Runtime Inventory ==
collected_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
host=$(hostname)
binary=$BIN_PATH
EOF_REPORT
fi

GATE_FAIL=0

{
  echo
  echo '-- version --'
  "$BIN_PATH" --version 2>/dev/null || true

  echo
  echo '-- file --'
  file "$BIN_PATH" 2>/dev/null || true

  echo
  echo '-- sha256 --'
  sha256 "$BIN_PATH" 2>/dev/null || true

  echo
  echo '-- ldd --'
  ldd "$BIN_PATH" 2>/dev/null || true

  echo
  echo '-- strings (selected runtime path probes) --'
  egrep '(@opentui/core-openbsd-x64/index.ts|libopentui\.so|/srv/opencode-port|\.bun/@opentui\+core@)' "$STRINGS_CACHE" \
    | head -80 || true

  echo
  echo '-- portability flags --'
  if grep -q '/srv/opencode-port' "$STRINGS_CACHE"; then
    echo 'contains_private_workspace_paths=yes'
  else
    echo 'contains_private_workspace_paths=no'
  fi
  if grep -q '@opentui/core-openbsd-x64/index.ts' "$STRINGS_CACHE"; then
    echo 'contains_opentui_openbsd_loader_ref=yes'
  else
    echo 'contains_opentui_openbsd_loader_ref=no'
  fi

  if [ -n "$FORBID_PATTERNS" ]; then
    echo
    echo '-- gate --'
    old_ifs=$IFS
    IFS='
'
    for pat in $FORBID_PATTERNS; do
      [ -n "$pat" ] || continue
      if egrep -q "$pat" "$STRINGS_CACHE"; then
        echo "forbid_match=yes pattern=$pat"
        GATE_FAIL=1
      else
        echo "forbid_match=no pattern=$pat"
      fi
    done
    IFS=$old_ifs
    if [ "$GATE_FAIL" -eq 1 ]; then
      echo 'gate_status=FAIL'
    else
      echo 'gate_status=PASS'
    fi
  fi
} >> "$OUTPUT_PATH"

echo "Wrote runtime inventory: $OUTPUT_PATH"

if [ "$GATE_FAIL" -eq 1 ]; then
  if [ "$FAIL_ON_PRIVATE_PATH" -eq 1 ]; then
    echo 'pkg-inventory.sh: gate failed (private workspace path(s) detected)' >&2
  else
    echo 'pkg-inventory.sh: gate failed (forbidden pattern match)' >&2
  fi
  exit 1
fi
