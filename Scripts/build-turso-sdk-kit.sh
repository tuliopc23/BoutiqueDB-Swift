#!/usr/bin/env bash
# Build vendored libturso_sdk_kit (official Turso language-binding C ABI).
#
# Official experimental feature enablement uses turso_database_config_t.experimental_features
# (comma-separated tokens from docs/sql-reference/experimental-features.mdx).
#
# Cargo features:
#   fts         — FTS index method module
#   encryption  — at-rest encryption support
#
# Usage:
#   ./Scripts/build-turso-sdk-kit.sh
#   TURSO_SRC=/path/to/BoutiqueDB ./Scripts/build-turso-sdk-kit.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TURSO_SRC="${TURSO_SRC:-$ROOT/../BoutiqueDB}"
if [[ ! -d "$TURSO_SRC/sdk-kit" && -d "$ROOT/../turso-src/sdk-kit" ]]; then
  TURSO_SRC="$ROOT/../turso-src"
fi

OUT_LIB_DIR="$ROOT/Vendor/turso-sdk/lib"
OUT_INCLUDE="$ROOT/Sources/CTursoSDK/include"
TURSO_SDK_FEATURES="${TURSO_SDK_FEATURES:-fts,encryption}"

if [[ ! -d "$TURSO_SRC/sdk-kit" ]]; then
  echo "Turso source with sdk-kit not found at $TURSO_SRC" >&2
  exit 1
fi

echo "Building turso_sdk_kit from $TURSO_SRC …"
echo "  cargo build -p turso_sdk_kit --release --features ${TURSO_SDK_FEATURES}"
(
  cd "$TURSO_SRC"
  # shellcheck disable=SC2086
  cargo build -p turso_sdk_kit --release --features ${TURSO_SDK_FEATURES}
)

LIB_CANDIDATES=(
  "$TURSO_SRC/target/release/libturso_sdk_kit.a"
  "$TURSO_SRC/target/release/deps/libturso_sdk_kit.a"
)
LIB=""
for c in "${LIB_CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then LIB="$c"; break; fi
done
if [[ -z "$LIB" ]]; then
  echo "libturso_sdk_kit.a not found" >&2
  exit 1
fi

mkdir -p "$OUT_LIB_DIR" "$OUT_INCLUDE"
cp "$LIB" "$OUT_LIB_DIR/libturso_sdk_kit.a"
cp "$TURSO_SRC/sdk-kit/turso.h" "$OUT_INCLUDE/turso.h"
printf '%s\n' 'module CTursoSDK {' '  header "turso.h"' '  export *' '}' \
  > "$OUT_INCLUDE/module.modulemap"
if [[ ! -f "$ROOT/Sources/CTursoSDK/empty.c" ]]; then
  echo '// CTursoSDK placeholder' > "$ROOT/Sources/CTursoSDK/empty.c"
fi

echo "Wrote:"
echo "  $OUT_LIB_DIR/libturso_sdk_kit.a"
echo "  $OUT_INCLUDE/turso.h"
echo ""
echo "Official open options: experimental_features CSV on turso_database_config_t"
echo "  e.g. views,index_method,encryption,multiprocess_wal,generated_columns,vacuum,without_rowid"
echo "Async: async_io=1 + TURSO_IO + turso_statement_run_io"
