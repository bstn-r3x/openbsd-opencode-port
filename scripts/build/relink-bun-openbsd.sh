#!/bin/sh
set -eu

usage() {
  cat <<USAGE
Usage: relink-bun-openbsd.sh --build-dir DIR --bun-obj FILE [--output-bin FILE]

Relinks a Bun OpenBSD binary from a rebuilt bun-zig.o using a V8 symbol trampoline
compat object, without mutating bun-zig.o symbols via llvm-objcopy --redefine-sym.

Options:
  --build-dir DIR   Bun CMake build directory (contains link.txt, openbsd_compat.o)
  --bun-obj FILE    Rebuilt bun-zig.o object to relink
  --output-bin FILE Copy final bun-profile to this path after relink (optional)
  -h, --help        Show this help

Env fallbacks:
  BUN_BUILD_DIR, BUN_ZIG_OBJECT, BUN_OUTPUT_BIN
USAGE
}

BUILD_DIR=${BUN_BUILD_DIR:-}
BUN_OBJ=${BUN_ZIG_OBJECT:-}
OUTPUT_BIN=${BUN_OUTPUT_BIN:-}

while [ $# -gt 0 ]; do
  case "$1" in
    --build-dir)
      BUILD_DIR=$2; shift 2 ;;
    --bun-obj)
      BUN_OBJ=$2; shift 2 ;;
    --output-bin)
      OUTPUT_BIN=$2; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

[ -n "$BUILD_DIR" ] || { echo "missing --build-dir" >&2; exit 2; }
[ -n "$BUN_OBJ" ] || { echo "missing --bun-obj" >&2; exit 2; }
[ -f "$BUN_OBJ" ] || { echo "bun object not found: $BUN_OBJ" >&2; exit 1; }

LINK_TXT="$BUILD_DIR/CMakeFiles/bun-profile.dir/link.txt"
OPENBSD_COMPAT_OBJ="$BUILD_DIR/openbsd_compat.o"

[ -f "$LINK_TXT" ] || { echo "link command file not found: $LINK_TXT" >&2; exit 1; }
[ -f "$OPENBSD_COMPAT_OBJ" ] || { echo "compat object not found: $OPENBSD_COMPAT_OBJ" >&2; exit 1; }

OBJCOPY=${OBJCOPY:-}
if [ -z "$OBJCOPY" ]; then
  if command -v llvm-objcopy >/dev/null 2>&1; then
    OBJCOPY=$(command -v llvm-objcopy)
  elif command -v objcopy >/dev/null 2>&1; then
    OBJCOPY=$(command -v objcopy)
  else
    echo "llvm-objcopy/objcopy not found" >&2
    exit 1
  fi
fi

CC=${CC:-clang}

TMPDIR_LOCAL=$(mktemp -d "$BUILD_DIR/.relink-bun.XXXXXX")
cleanup() {
  rm -rf "$TMPDIR_LOCAL"
}
trap cleanup EXIT INT TERM

TMP_OBJ="$TMPDIR_LOCAL/bun-zig.relink.o"
TMP_ASM="$TMPDIR_LOCAL/v8_symbol_trampoline.s"
TMP_TRAMP_OBJ="$TMPDIR_LOCAL/v8_symbol_trampoline.o"

cp "$BUN_OBJ" "$TMP_OBJ"
"$OBJCOPY" --strip-debug "$TMP_OBJ"
printf '\014' | dd of="$TMP_OBJ" bs=1 seek=7 conv=notrunc >/dev/null 2>&1

SYM_SRC='_ZN2v85Array3NewENS_5LocalINS_7ContextEEEmSt8functionIFNS_10MaybeLocalINS_5ValueEEEvEE'
SYM_DST='_ZN2v85Array3NewENS_5LocalINS_7ContextEEEmNSt3__18functionIFNS_10MaybeLocalINS_5ValueEEEvEEE'

cat > "$TMP_ASM" <<ASM
    .text
    .globl ${SYM_SRC}
    .type ${SYM_SRC},@function
${SYM_SRC}:
    jmp ${SYM_DST}
ASM
"$CC" -c -o "$TMP_TRAMP_OBJ" "$TMP_ASM"

cmd=$(sed -n '1p' "$LINK_TXT")
cmd=$(printf '%s' "$cmd" | sed 's#"bun-zig.o"#"'"$TMP_OBJ"'"#')
case "$cmd" in
  *"openbsd_compat.o"*)
    cmd=$(printf '%s' "$cmd" | sed 's# openbsd_compat.o # openbsd_compat.o "'"$TMP_TRAMP_OBJ"'" #')
    ;;
  *)
    cmd=$(printf '%s' "$cmd" | sed 's# -o bun-profile # "'"$OPENBSD_COMPAT_OBJ"'" "'"$TMP_TRAMP_OBJ"'" -o bun-profile #')
    ;;
esac

( cd "$BUILD_DIR" && eval "$cmd" )

if [ -n "$OUTPUT_BIN" ]; then
  cp "$BUILD_DIR/bun-profile" "$OUTPUT_BIN"
fi

echo "relink_ok"
echo "build_dir=$BUILD_DIR"
echo "bun_profile=$BUILD_DIR/bun-profile"
if [ -n "$OUTPUT_BIN" ]; then
  echo "output_bin=$OUTPUT_BIN"
fi
