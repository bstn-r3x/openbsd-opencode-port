#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/pkg-stage.sh [options]

Stage a local-package image tree using standard OpenBSD install locations.
This prepares files under a package image root for a later pkg_create step.

Options:
  --bin PATH         Compiled OpenCode binary to package
                     (default: /srv/opencode-port/opencode/packages/opencode/dist/opencode-openbsd-x64/bin/opencode)
  --root PATH        Package image root (default: <repo>/port/pkg-stage/image)
  --prefix PATH      Install prefix inside package (default: /usr/local)
  --doc-name NAME    Doc dir name under share/doc (default: opencode)
  --version VERSION  Override detected version
  --force            Remove existing package image root first
  -h, --help         Show this help
USAGE
}

die() {
  echo "pkg-stage.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

BIN_PATH="/srv/opencode-port/opencode/packages/opencode/dist/opencode-openbsd-x64/bin/opencode"
IMAGE_ROOT="$PORT_DIR/pkg-stage/image"
PREFIX="/usr/local"
DOC_NAME="opencode"
VERSION=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bin)
      [ $# -ge 2 ] || die "missing value for --bin"
      BIN_PATH=$2
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || die "missing value for --root"
      IMAGE_ROOT=$2
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
    --version)
      [ $# -ge 2 ] || die "missing value for --version"
      VERSION=$2
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

[ -x "$BIN_PATH" ] || die "binary is not executable: $BIN_PATH"
if [ -z "$VERSION" ]; then
  VERSION=$($BIN_PATH --version 2>/dev/null | head -1 | tr -d '\r')
fi
[ -n "$VERSION" ] || die "could not detect version"

if [ -e "$IMAGE_ROOT" ]; then
  if [ "$FORCE" -ne 1 ]; then
    die "package image root exists: $IMAGE_ROOT (use --force)"
  fi
  rm -rf -- "$IMAGE_ROOT"
fi

PREFIX_REL=${PREFIX#/}
BIN_DST="$IMAGE_ROOT/$PREFIX_REL/bin/opencode"
LIBEXEC_DIR="$IMAGE_ROOT/$PREFIX_REL/libexec/opencode"
DOC_DIR="$IMAGE_ROOT/$PREFIX_REL/share/doc/$DOC_NAME"
META_DIR="$IMAGE_ROOT/.pkg-meta"

mkdir -p "$(dirname -- "$BIN_DST")" "$LIBEXEC_DIR" "$DOC_DIR" "$META_DIR"

cat > "$BIN_DST" <<EOF_WRAP
#!/bin/sh
set -eu
exec $PREFIX/libexec/opencode/opencode-bin "\$@"
EOF_WRAP
chmod 755 "$BIN_DST"

cp -p "$BIN_PATH" "$LIBEXEC_DIR/opencode-bin"
chmod 755 "$LIBEXEC_DIR/opencode-bin"

cat > "$DOC_DIR/README.txt" <<EOF_DOC
OpenCode for OpenBSD (local package image)

Version: $VERSION
Install command (local package, future step): pkg_add ./<package-file>.tgz
Run command after install: opencode

Installed paths planned:
- $PREFIX/bin/opencode
- $PREFIX/libexec/opencode/opencode-bin
- $PREFIX/share/doc/$DOC_NAME/
EOF_DOC

cat > "$DOC_DIR/TROUBLESHOOTING.txt" <<'EOF_TROUBLE'
If the TUI appears mostly black or low-contrast in tmux:
- Use xterm-256color in the terminal emulator
- Set tmux default-terminal to tmux-256color
- Enable tmux truecolor overrides (Tc / RGB)
- Reattach tmux after changing terminal settings
EOF_TROUBLE

cat > "$META_DIR/INSTALL-LAYOUT.txt" <<EOF_META
prefix=$PREFIX
version=$VERSION
wrapper=$PREFIX/bin/opencode
binary=$PREFIX/libexec/opencode/opencode-bin
docdir=$PREFIX/share/doc/$DOC_NAME
binary_source=$BIN_PATH
staged_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
host=$(hostname)
EOF_META

cat > "$META_DIR/PLIST.candidate" <<EOF_PLIST
@name opencode-$VERSION
bin/opencode
libexec/opencode/opencode-bin
share/doc/$DOC_NAME/README.txt
share/doc/$DOC_NAME/TROUBLESHOOTING.txt
EOF_PLIST

echo "Staged local package image root: $IMAGE_ROOT"
echo "Install prefix: $PREFIX"
echo "Version: $VERSION"
echo "Planned installed files:"
echo "  $PREFIX/bin/opencode"
echo "  $PREFIX/libexec/opencode/opencode-bin"
echo "  $PREFIX/share/doc/$DOC_NAME/README.txt"
echo "  $PREFIX/share/doc/$DOC_NAME/TROUBLESHOOTING.txt"
