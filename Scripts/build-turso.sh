#!/usr/bin/env bash
# Build vendored libturso_sqlite3 for BoutiqueDB-Swift.
#
# Experimental features (FTS/vector index methods, views, encryption) are
# controlled by the Turso crate features / RUSTFLAGS available in your turso
# checkout. Override with TURSO_CARGO_ARGS.
#
# Example (adjust to your turso version's feature names):
#   TURSO_CARGO_ARGS='--features experimental' ./Scripts/build-turso.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TURSO_SRC="${TURSO_SRC:-$ROOT/../turso-src}"
# Prefer monorepo BoutiqueDB checkout when present (same machine layout).
if [[ ! -d "$TURSO_SRC/bindings/c" && -d "$ROOT/../BoutiqueDB/bindings/c" ]]; then
  TURSO_SRC="$ROOT/../BoutiqueDB"
fi
OUT_XCFRAMEWORK="$ROOT/Vendor/TursoSQLite3.xcframework"
TURSO_CARGO_ARGS="${TURSO_CARGO_ARGS:-}"

if [[ ! -d "$TURSO_SRC/bindings/c" ]]; then
  echo "Turso source not found at $TURSO_SRC" >&2
  echo "Clone the BoutiqueDB/turso engine repo and set TURSO_SRC." >&2
  exit 1
fi

echo "Building turso_sqlite3 from $TURSO_SRC …"
echo "  cargo build -p turso_sqlite3 --release ${TURSO_CARGO_ARGS}"
(
  cd "$TURSO_SRC"
  # shellcheck disable=SC2086
  cargo build -p turso_sqlite3 --release ${TURSO_CARGO_ARGS}
)

# Resolve artifact path (release).
LIB_CANDIDATES=(
  "$TURSO_SRC/target/release/libturso_sqlite3.a"
  "$TURSO_SRC/target/release/deps/libturso_sqlite3.a"
)
LIB=""
for c in "${LIB_CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then LIB="$c"; break; fi
done
if [[ -z "$LIB" ]]; then
  echo "libturso_sqlite3.a not found under $TURSO_SRC/target/release" >&2
  exit 1
fi

mkdir -p "$ROOT/Vendor/turso/include" "$ROOT/Vendor/turso/lib" /tmp/turso-headers
cp "$TURSO_SRC/bindings/c/include/sqlite3.h" "$ROOT/Vendor/turso/include/"
cp "$LIB" "$ROOT/Vendor/turso/lib/libturso_sqlite3.a"

# Keep Sources/CTursoSQLite3 headers in sync for the SPM C target.
mkdir -p "$ROOT/Sources/CTursoSQLite3/include"
cp "$ROOT/Vendor/turso/include/sqlite3.h" "$ROOT/Sources/CTursoSQLite3/include/"
printf '%s\n' 'module CTursoSQLite3 {' '  header "sqlite3.h"' '  export *' '}' \
  > "$ROOT/Sources/CTursoSQLite3/include/module.modulemap"

# XCFramework for Xcode app targets / future binary SPM target (SPI path).
mkdir -p /tmp/turso-headers
cp "$ROOT/Vendor/turso/include/sqlite3.h" /tmp/turso-headers/
printf '%s\n' 'module CTursoSQLite3 {' '  header "sqlite3.h"' '  export *' '}' \
  > /tmp/turso-headers/module.modulemap

rm -rf "$OUT_XCFRAMEWORK"
xcodebuild -create-xcframework \
  -library "$ROOT/Vendor/turso/lib/libturso_sqlite3.a" \
  -headers /tmp/turso-headers \
  -output "$OUT_XCFRAMEWORK"

echo "Wrote:"
echo "  $ROOT/Vendor/turso/lib/libturso_sqlite3.a"
echo "  $OUT_XCFRAMEWORK"
echo "  Sources/CTursoSQLite3/include"
echo ""
echo "Notes:"
echo "  • FTS/vector indexes and materialized views may need experimental features"
echo "    enabled at engine build time (see BoutiqueDB-Refinement-Tasks R1.1)."
echo "  • Runtime probes: BoutiqueDB.capabilities after open."
