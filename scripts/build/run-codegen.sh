#!/bin/bash
# Run Bun codegen scripts on Mac host to generate C++/Zig source files
# These are then copied to OpenBSD for the build

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${REPO_ROOT}}"
CWD="${WORKSPACE_ROOT}/bun-source"
CODEGEN_PATH="${CWD}/build/codegen"
BUILD_PATH="${CWD}/build"
BUN="${BUN:-bun}"
ESBUILD="$CWD/node_modules/.bin/esbuild"

mkdir -p "$CODEGEN_PATH"
cd "$CWD"

echo "=== 1. Generating ErrorCode files ==="
$BUN run src/codegen/generate-node-errors.ts "$CODEGEN_PATH"

echo "=== 2. Generating ZigGeneratedClasses ==="
# Read source list
CLASSES_SOURCES=$(cat cmake/sources/ZigGeneratedClassesSources.txt | sed "s|^|$CWD/|" | tr '\n' ' ')
$BUN run src/codegen/generate-classes.ts $CLASSES_SOURCES "$CODEGEN_PATH"

echo "=== 3. Generating JavaScript modules (bundle-modules) ==="
$BUN run src/codegen/bundle-modules.ts --debug=OFF "$BUILD_PATH"

echo "=== 4. Generating C++ --> Zig bindings (cppbind) ==="
$BUN src/codegen/cppbind.ts src "$CODEGEN_PATH"

echo "=== 5. Generating CI info ==="
$BUN src/codegen/ci_info.ts "$CODEGEN_PATH/ci_info.zig"

echo "=== 6. Generating JSSink ==="
$BUN run src/codegen/generate-jssink.ts "$CODEGEN_PATH"

echo "=== 7. Generating Bake codegen ==="
$BUN run src/codegen/bake-codegen.ts --debug=OFF --codegen-root="$CODEGEN_PATH"

echo "=== 8. Generating bindings v2 ==="
BINDGENV2_SOURCES=$(cat cmake/sources/BindgenV2Sources.txt | sed "s|^|$CWD/|" | tr '\n' ',')
$BUN run src/codegen/bindgenv2/script.ts --command=generate --sources="$BINDGENV2_SOURCES" --codegen-path="$CODEGEN_PATH"

echo "=== 9. Generating binding generator ==="
$BUN run src/codegen/bindgen.ts --codegen-root="$CODEGEN_PATH"

echo "=== 10. Building esbuild bundles ==="
# bun-error
mkdir -p "$CODEGEN_PATH/bun-error"
cd "$CWD/packages/bun-error"
$BUN install 2>/dev/null || true
$ESBUILD index.tsx bun-error.css --outdir="$CODEGEN_PATH/bun-error" --define:process.env.NODE_ENV=\"\'production\'\" --minify --bundle --platform=browser --format=esm
cd "$CWD"

# fallback-decoder
$ESBUILD src/fallback.ts --outfile="$CODEGEN_PATH/fallback-decoder.js" --target=esnext --bundle --format=iife --platform=browser --minify

# runtime.out.js
$ESBUILD src/runtime.bun.js --outfile="$CODEGEN_PATH/runtime.out.js" --define:process.env.NODE_ENV=\"\'production\'\" --target=esnext --bundle --format=esm --platform=node --minify --external:/bun:*

echo "=== 11. Building node-fallbacks ==="
cd "$CWD/src/node-fallbacks"
$BUN install 2>/dev/null || true
$BUN run build-fallbacks "$CODEGEN_PATH/node-fallbacks"
cd "$CWD"

echo "=== 12. Generating LUT hash tables ==="
# Create LUT tables from ZigGeneratedClasses.lut.txt
if [ -f "$CODEGEN_PATH/ZigGeneratedClasses.lut.txt" ]; then
  while IFS= read -r line; do
    LUTFILE=$(echo "$line" | awk '{print $1}')
    LUTSRC=$(echo "$line" | awk '{print $2}')
    if [ -n "$LUTFILE" ] && [ -n "$LUTSRC" ]; then
      echo "  LUT: $LUTFILE"
      $BUN run src/codegen/create-hash-table.ts "$LUTSRC" "$CODEGEN_PATH/$LUTFILE"
    fi
  done < "$CODEGEN_PATH/ZigGeneratedClasses.lut.txt"
fi

echo ""
echo "=== CODEGEN COMPLETE ==="
echo "Output in: $CODEGEN_PATH"
ls -la "$CODEGEN_PATH/" | head -30
