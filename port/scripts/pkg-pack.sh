#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/pkg-pack.sh [options]

Create a real local OpenBSD package (.tgz for pkg_add) from a staged package image.

Options:
  --root PATH         Package image root (default: <repo>/port/pkg-stage/image)
  --out-dir PATH      Output directory for package archives (default: <repo>/port/pkg-stage/packages)
  --work-dir PATH     Working directory for generated plist/desc (default: <repo>/port/pkg-stage/work)
  --prefix PATH       Install prefix recorded in package (default: /usr/local)
  --doc-name NAME     Doc dir name under share/doc (default: opencode)
  --stem NAME         Package stem/name prefix (default: opencode)
  --version VERSION   Override detected app version (default: detect from staged binary --version)
  --comment TEXT      Package COMMENT field (default: OpenCode local package for OpenBSD)
  --fullpkgpath PATH  Package FULLPKGPATH metadata (default: misc/opencode)
  --desc PATH         Use description text from file instead of generated text
  --inventory-check   Run pkg-inventory.sh on the staged binary before pkg_create (report only)
  --inventory-gate    Run pkg-inventory.sh --fail-on-private-path before pkg_create (fails on leak)
  --inventory-output PATH
                      Output path for inventory report when using --inventory-check/--inventory-gate
                      (default: pkg-inventory.sh default report path)
  --force             Overwrite existing package/checksum and reset work dir
  -h, --help          Show this help
USAGE
}

die() {
  echo "pkg-pack.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

IMAGE_ROOT="$PORT_DIR/pkg-stage/image"
OUT_DIR="$PORT_DIR/pkg-stage/packages"
WORK_DIR="$PORT_DIR/pkg-stage/work"
PREFIX="/usr/local"
DOC_NAME="opencode"
STEM="opencode"
VERSION=""
COMMENT="OpenCode local package for OpenBSD"
FULLPKGPATH="misc/opencode"
DESC_PATH=""
INVENTORY_MODE=""
INVENTORY_OUTPUT=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || die "missing value for --root"
      IMAGE_ROOT=$2
      shift 2
      ;;
    --out-dir)
      [ $# -ge 2 ] || die "missing value for --out-dir"
      OUT_DIR=$2
      shift 2
      ;;
    --work-dir)
      [ $# -ge 2 ] || die "missing value for --work-dir"
      WORK_DIR=$2
      shift 2
      ;;
    --prefix)
      [ $# -ge 2 ] || die "missing value for --prefix"
      PREFIX=$2
      shift 2
      ;;
    --doc-name)
      [ $# -ge 2 ] || die "missing value for --doc-name"
      DOC_NAME=$2
      shift 2
      ;;
    --stem)
      [ $# -ge 2 ] || die "missing value for --stem"
      STEM=$2
      shift 2
      ;;
    --version)
      [ $# -ge 2 ] || die "missing value for --version"
      VERSION=$2
      shift 2
      ;;
    --comment)
      [ $# -ge 2 ] || die "missing value for --comment"
      COMMENT=$2
      shift 2
      ;;
    --fullpkgpath)
      [ $# -ge 2 ] || die "missing value for --fullpkgpath"
      FULLPKGPATH=$2
      shift 2
      ;;
    --desc)
      [ $# -ge 2 ] || die "missing value for --desc"
      DESC_PATH=$2
      shift 2
      ;;
    --inventory-check)
      INVENTORY_MODE=check
      shift
      ;;
    --inventory-gate)
      INVENTORY_MODE=gate
      shift
      ;;
    --inventory-output)
      [ $# -ge 2 ] || die "missing value for --inventory-output"
      INVENTORY_OUTPUT=$2
      shift 2
      ;;
    --force)
      FORCE=1
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

case "$PREFIX" in
  /usr/local|/usr/local/*) : ;;
  *) die "prefix must be under /usr/local for standard OpenBSD package layout (got: $PREFIX)" ;;
esac

[ -d "$IMAGE_ROOT" ] || die "image root not found: $IMAGE_ROOT"
PREFIX_REL=${PREFIX#/}
WRAPPER_PATH="$IMAGE_ROOT/$PREFIX_REL/bin/opencode"
BIN_PATH="$IMAGE_ROOT/$PREFIX_REL/libexec/opencode/opencode-bin"
DOC_README="$IMAGE_ROOT/$PREFIX_REL/share/doc/$DOC_NAME/README.txt"
DOC_TROUBLE="$IMAGE_ROOT/$PREFIX_REL/share/doc/$DOC_NAME/TROUBLESHOOTING.txt"

[ -x "$WRAPPER_PATH" ] || die "staged wrapper not found: $WRAPPER_PATH"
[ -x "$BIN_PATH" ] || die "staged binary not found: $BIN_PATH"
[ -f "$DOC_README" ] || die "staged doc not found: $DOC_README"
[ -f "$DOC_TROUBLE" ] || die "staged doc not found: $DOC_TROUBLE"

if [ -n "$INVENTORY_MODE" ]; then
  INVENTORY_SCRIPT="$SCRIPT_DIR/pkg-inventory.sh"
  [ -x "$INVENTORY_SCRIPT" ] || die "inventory script not executable: $INVENTORY_SCRIPT"
  echo "Running inventory preflight ($INVENTORY_MODE) on staged binary..."
  if [ "$INVENTORY_MODE" = "gate" ]; then
    if [ -n "$INVENTORY_OUTPUT" ]; then
      "$INVENTORY_SCRIPT" --bin "$BIN_PATH" --output "$INVENTORY_OUTPUT" --fail-on-private-path
    else
      "$INVENTORY_SCRIPT" --bin "$BIN_PATH" --fail-on-private-path
    fi
  else
    if [ -n "$INVENTORY_OUTPUT" ]; then
      "$INVENTORY_SCRIPT" --bin "$BIN_PATH" --output "$INVENTORY_OUTPUT"
    else
      "$INVENTORY_SCRIPT" --bin "$BIN_PATH"
    fi
  fi
fi

if [ -z "$VERSION" ]; then
  VERSION=$($BIN_PATH --version 2>/dev/null | head -1 | tr -d '\r')
fi
[ -n "$VERSION" ] || die "could not detect version"

PKG_VERSION=$(printf '%s' "$VERSION" | sed 's/[^A-Za-z0-9._]/./g; s/\.\{2,\}/./g; s/^\.//; s/\.$//')
[ -n "$PKG_VERSION" ] || die "could not derive a valid package version from: $VERSION"
PKG_NAME="$STEM-$PKG_VERSION"

PKG_PATH="$OUT_DIR/$PKG_NAME.tgz"
CHECKSUM_PATH="$PKG_PATH.sha256"
PLIST_PATH="$WORK_DIR/$PKG_NAME.plist"
GEN_DESC_PATH="$WORK_DIR/$PKG_NAME.DESCR"

mkdir -p "$OUT_DIR"
if [ -e "$WORK_DIR" ] && [ "$FORCE" -eq 1 ]; then
  rm -rf -- "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"

if [ -e "$PKG_PATH" ] || [ -e "$CHECKSUM_PATH" ]; then
  if [ "$FORCE" -ne 1 ]; then
    die "package or checksum already exists (use --force): $PKG_NAME.tgz"
  fi
  rm -f -- "$PKG_PATH" "$CHECKSUM_PATH"
fi

cat > "$PLIST_PATH" <<EOF_PLIST
@cwd $PREFIX
bin/opencode
libexec/opencode/opencode-bin
share/doc/$DOC_NAME/README.txt
share/doc/$DOC_NAME/TROUBLESHOOTING.txt
EOF_PLIST

if [ -n "$DESC_PATH" ]; then
  [ -f "$DESC_PATH" ] || die "desc file not found: $DESC_PATH"
  DESC_TO_USE=$DESC_PATH
else
  cat > "$GEN_DESC_PATH" <<EOF_DESC
OpenCode local package for OpenBSD.

This package is generated by the local packaging workflow in port/scripts/
and is intended for pkg_add/pkg_delete validation before publishing via a
local package repository or upstream OpenBSD ports integration.

OpenCode application version: $VERSION
Package version (sanitized for pkg_create): $PKG_VERSION

Installed files:
- $PREFIX/bin/opencode
- $PREFIX/libexec/opencode/opencode-bin
- $PREFIX/share/doc/$DOC_NAME/README.txt
- $PREFIX/share/doc/$DOC_NAME/TROUBLESHOOTING.txt
EOF_DESC
  DESC_TO_USE=$GEN_DESC_PATH
fi

pkg_create \
  -v \
  -B "$IMAGE_ROOT" \
  -d "$DESC_TO_USE" \
  -D COMMENT="$COMMENT" \
  -D FULLPKGPATH="$FULLPKGPATH" \
  -D PORTSDIR=/usr/ports \
  -D MAINTAINER=local@opencode.invalid \
  -f "$PLIST_PATH" \
  -p "$PREFIX" \
  "$PKG_PATH"

( cd "$OUT_DIR" && sha256 "$(basename -- "$PKG_PATH")" > "$(basename -- "$CHECKSUM_PATH")" )

echo "Package:         $PKG_PATH"
echo "Checksum:        $CHECKSUM_PATH"
echo "App version:     $VERSION"
echo "Package version: $PKG_VERSION"
echo "Install:         pkg_add ./${PKG_NAME}.tgz"
echo "Delete:          pkg_delete $PKG_NAME"
