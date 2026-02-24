#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: port/scripts/source-vendor-prep.sh [options]

Prepare a clean-clone OpenCode source workspace for Option 1 (source-distfile) ports work,
using the validated filtered Bun workspace install on OpenBSD.

This script can optionally produce two maintainer artifacts:
- source tarball (tracked files from git archive)
- filtered dependency payload tarball (node_modules + packages/opencode/node_modules)

Options:
  --source-repo PATH   OpenCode source repo to clone
                       (default: /srv/opencode-port/publish/repos/opencode-openbsd)
  --bun PATH          Bun binary to use for install/build steps (default: /srv/opencode-port/bun)
  --work-dir PATH     Workspace dir to create (default: /srv/opencode-port/tmp/opencode-source-prep)
  --tmpdir PATH       TMPDIR for bun install/build (default: /srv/opencode-port/tmp)
  --filter VALUE      Bun workspace filter (default: ./packages/opencode)
  --archive-dir PATH  Output dir for source/vendor tarballs + SHA256 (optional)
  --skip-build-smoke  Skip build smoke (default: run build.ts --single --skip-install)
  --force             Remove existing work dir first
  -h, --help          Show this help
USAGE
}

die() {
  echo "source-vendor-prep.sh: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found in PATH: $1"
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

SOURCE_REPO="/srv/opencode-port/publish/repos/opencode-openbsd"
BUN_BIN="/srv/opencode-port/bun"
WORK_DIR="/srv/opencode-port/tmp/opencode-source-prep"
TMPDIR_PATH="/srv/opencode-port/tmp"
FILTER="./packages/opencode"
ARCHIVE_DIR=""
RUN_BUILD_SMOKE=1
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --source-repo)
      [ $# -ge 2 ] || die "missing value for --source-repo"
      SOURCE_REPO=$2
      shift 2
      ;;
    --bun)
      [ $# -ge 2 ] || die "missing value for --bun"
      BUN_BIN=$2
      shift 2
      ;;
    --work-dir)
      [ $# -ge 2 ] || die "missing value for --work-dir"
      WORK_DIR=$2
      shift 2
      ;;
    --tmpdir)
      [ $# -ge 2 ] || die "missing value for --tmpdir"
      TMPDIR_PATH=$2
      shift 2
      ;;
    --filter)
      [ $# -ge 2 ] || die "missing value for --filter"
      FILTER=$2
      shift 2
      ;;
    --archive-dir)
      [ $# -ge 2 ] || die "missing value for --archive-dir"
      ARCHIVE_DIR=$2
      shift 2
      ;;
    --skip-build-smoke)
      RUN_BUILD_SMOKE=0
      shift
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

[ -d "$SOURCE_REPO/.git" ] || die "source repo not found (expected git repo): $SOURCE_REPO"
[ -x "$BUN_BIN" ] || die "bun binary is not executable: $BUN_BIN"

need_cmd git
need_cmd tar
need_cmd du
need_cmd df
need_cmd awk
need_cmd sha256
need_cmd node
need_cmd node-gyp
need_cmd python3
need_cmd gmake

mkdir -p "$TMPDIR_PATH"

# Bun compile can fail with ENOSPC on small /tmp; provide an early warning.
TMPDIR_AVAIL_KB=$(df -Pk "$TMPDIR_PATH" | awk 'NR==2 {print $4}')
case "$TMPDIR_AVAIL_KB" in
  ''|*[!0-9]*) TMPDIR_AVAIL_KB=0 ;;
esac
if [ "$TMPDIR_AVAIL_KB" -lt 2000000 ]; then
  echo "Warning: TMPDIR free space is below ~2GB: $TMPDIR_PATH (${TMPDIR_AVAIL_KB} KB available)" >&2
fi

if [ -e "$WORK_DIR" ]; then
  if [ "$FORCE" -ne 1 ]; then
    die "work dir exists: $WORK_DIR (use --force)"
  fi
  rm -rf -- "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
REPO_DIR="$WORK_DIR/repo"

echo "Cloning OpenCode source repo..."
git clone -q "$SOURCE_REPO" "$REPO_DIR"
COMMIT=$(git -C "$REPO_DIR" rev-parse --short HEAD)
VERSION_HINT=$(git -C "$REPO_DIR" log -1 --format=%cd --date=format:%Y%m%d%H%M HEAD 2>/dev/null || echo unknown)

echo "Commit: $COMMIT"
echo "Running filtered bun install: $FILTER"
(
  cd "$REPO_DIR"
  TMPDIR="$TMPDIR_PATH" "$BUN_BIN" install --frozen-lockfile --filter="$FILTER"
)

NODE_BUN_SIZE=$(cd "$REPO_DIR" && du -sh node_modules/.bun | awk '{print $1}')
WORKSPACE_NODE_SIZE=$(cd "$REPO_DIR" && du -sh packages/opencode/node_modules | awk '{print $1}')

echo "Filtered dependency payload ready"
echo "  node_modules/.bun: $NODE_BUN_SIZE"
echo "  packages/opencode/node_modules: $WORKSPACE_NODE_SIZE"

BUILD_VERSION=""
if [ "$RUN_BUILD_SMOKE" -eq 1 ]; then
  echo "Running build smoke: packages/opencode/script/build.ts --single --skip-install"
  (
    cd "$REPO_DIR"
    TMPDIR="$TMPDIR_PATH" OPENCODE_BUILD_SANITIZE_PATHS=0 \
      "$BUN_BIN" run --cwd packages/opencode script/build.ts --single --skip-install
  )
  BUILD_VERSION=$(
    "$REPO_DIR/packages/opencode/dist/opencode-openbsd-x64/bin/opencode" --version 2>/dev/null | head -1 | tr -d '\r' || true
  )
  [ -n "$BUILD_VERSION" ] || die "build smoke succeeded but version check failed"
  echo "Build smoke version: $BUILD_VERSION"
fi

SRC_TARBALL=""
VENDOR_TARBALL=""
SHA_FILE=""
if [ -n "$ARCHIVE_DIR" ]; then
  mkdir -p "$ARCHIVE_DIR"
  SRC_TARBALL="$ARCHIVE_DIR/opencode-source-$COMMIT.tar.gz"
  VENDOR_TARBALL="$ARCHIVE_DIR/opencode-filtered-deps-$COMMIT.tar.gz"
  SHA_FILE="$ARCHIVE_DIR/SHA256"

  echo "Creating source tarball (tracked files via git archive)..."
  git -C "$REPO_DIR" archive --format=tar.gz --output "$SRC_TARBALL" HEAD

  echo "Creating filtered dependency payload tarball..."
  (
    cd "$REPO_DIR"
    tar -czf "$VENDOR_TARBALL" node_modules packages/opencode/node_modules
  )

  sha256 "$SRC_TARBALL" "$VENDOR_TARBALL" > "$SHA_FILE"
  echo "Wrote archives:"
  echo "  $SRC_TARBALL"
  echo "  $VENDOR_TARBALL"
  echo "  $SHA_FILE"
fi

REPORT="$WORK_DIR/REPORT.txt"
cat > "$REPORT" <<EOF_REPORT
source_repo=$SOURCE_REPO
repo_commit=$COMMIT
work_dir=$WORK_DIR
tmpdir=$TMPDIR_PATH
bun=$BUN_BIN
filter=$FILTER
node_modules_bun_size=$NODE_BUN_SIZE
packages_opencode_node_modules_size=$WORKSPACE_NODE_SIZE
build_smoke=$( [ "$RUN_BUILD_SMOKE" -eq 1 ] && echo yes || echo no )
build_version=$BUILD_VERSION
archive_dir=$ARCHIVE_DIR
source_tarball=$SRC_TARBALL
vendor_tarball=$VENDOR_TARBALL
sha256_file=$SHA_FILE
prepared_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
host=$(hostname)
EOF_REPORT

echo "Report: $REPORT"
