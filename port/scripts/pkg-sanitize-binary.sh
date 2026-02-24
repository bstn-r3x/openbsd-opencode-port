#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/pkg-sanitize-binary.sh [options]

Sanitize embedded private build-path prefixes in a Bun-compiled binary payload using
an in-place same-length byte replacement (no strip).

This is a legacy fallback packaging hygiene step for binaries that were built before
source-level path sanitization was added to the OpenCode build pipeline.

Options:
  --bin PATH       Binary to patch in place
                   (default: <repo>/port/pkg-stage/image/usr/local/libexec/opencode/opencode-bin)
  --from STRING    Prefix to replace (default: /srv/opencode-port/opencode)
  --to STRING      Replacement prefix; must be same length as --from
                   (default: /usr/obj/opencode-build____)
  --dry-run        Report matches but do not modify the file
  --no-version     Skip before/after --version checks
  -h, --help       Show this help
USAGE
}

die() {
  echo "pkg-sanitize-binary.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

BIN_PATH="$PORT_DIR/pkg-stage/image/usr/local/libexec/opencode/opencode-bin"
FROM_PREFIX="/srv/opencode-port/opencode"
TO_PREFIX="/usr/obj/opencode-build____"
DRY_RUN=0
CHECK_VERSION=1

while [ $# -gt 0 ]; do
  case "$1" in
    --bin)
      [ $# -ge 2 ] || die "missing value for --bin"
      BIN_PATH=$2
      shift 2
      ;;
    --from)
      [ $# -ge 2 ] || die "missing value for --from"
      FROM_PREFIX=$2
      shift 2
      ;;
    --to)
      [ $# -ge 2 ] || die "missing value for --to"
      TO_PREFIX=$2
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-version)
      CHECK_VERSION=0
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

[ -f "$BIN_PATH" ] || die "binary not found: $BIN_PATH"
[ -r "$BIN_PATH" ] || die "binary is not readable: $BIN_PATH"
[ "${#FROM_PREFIX}" -eq "${#TO_PREFIX}" ] || die "--from and --to must have equal length (${#FROM_PREFIX} != ${#TO_PREFIX})"

BEFORE_COUNT=$(strings -a "$BIN_PATH" 2>/dev/null | grep -F -c "$FROM_PREFIX" || true)
BEFORE_VERSION=""
if [ "$CHECK_VERSION" -eq 1 ] && [ -x "$BIN_PATH" ]; then
  BEFORE_VERSION=$($BIN_PATH --version 2>/dev/null | head -1 | tr -d '\r' || true)
fi

echo "Binary:          $BIN_PATH"
echo "From prefix:     $FROM_PREFIX"
echo "To prefix:       $TO_PREFIX"
echo "Matches before:  $BEFORE_COUNT"
[ "$CHECK_VERSION" -eq 1 ] && echo "Version before:  ${BEFORE_VERSION:-<none>}"

if [ "$DRY_RUN" -eq 1 ]; then
  exit 0
fi

REPLACEMENTS=$(perl -e '
  use strict; use warnings;
  my ($file, $from, $to) = @ARGV;
  die "length mismatch\n" unless length($from) == length($to);
  local $/;
  open my $fh, q{<}, $file or die "open: $!\n";
  binmode $fh;
  my $data = <$fh>;
  close $fh;
  my $count = ($data =~ s/\Q$from\E/$to/g);
  open my $oh, q{>}, $file or die "write: $!\n";
  binmode $oh;
  print {$oh} $data or die "print: $!\n";
  close $oh;
  print $count;
' "$BIN_PATH" "$FROM_PREFIX" "$TO_PREFIX")

AFTER_COUNT=$(strings -a "$BIN_PATH" 2>/dev/null | grep -F -c "$FROM_PREFIX" || true)
TO_COUNT=$(strings -a "$BIN_PATH" 2>/dev/null | grep -F -c "$TO_PREFIX" || true)
AFTER_VERSION=""
if [ "$CHECK_VERSION" -eq 1 ] && [ -x "$BIN_PATH" ]; then
  AFTER_VERSION=$($BIN_PATH --version 2>/dev/null | head -1 | tr -d '\r' || true)
fi

echo "Replacements:    $REPLACEMENTS"
echo "Matches after:   $AFTER_COUNT"
echo "New prefix hits: $TO_COUNT"
[ "$CHECK_VERSION" -eq 1 ] && echo "Version after:   ${AFTER_VERSION:-<none>}"

if [ "$CHECK_VERSION" -eq 1 ] && [ -n "$BEFORE_VERSION" ] && [ -n "$AFTER_VERSION" ] && [ "$BEFORE_VERSION" != "$AFTER_VERSION" ]; then
  die "version changed after sanitization ($BEFORE_VERSION -> $AFTER_VERSION)"
fi

if [ "$AFTER_COUNT" -ne 0 ]; then
  die "private prefix still present after sanitization"
fi
