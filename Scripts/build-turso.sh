#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TURSO_SRC="${TURSO_SRC:-$ROOT/../turso-src}"
OUT_XCFRAMEWORK="$ROOT/Vendor/TursoSQLite3.xcframework"

if [[ ! -d "$TURSO_SRC/bindings/c" ]]; then
  echo "Turso source not found at $TURSO_SRC" >&2
  echo "Clone https://github.com/tursodatabase/turso and set TURSO_SRC." >&2
  exit 1
fi

echo "Building turso_sqlite3 (release)…"
(
  cd "$TURSO_SRC"
  cargo build -p turso_sqlite3 --release
)

mkdir -p "$ROOT/Vendor/turso/include" "$ROOT/Vendor/turso/lib" /tmp/turso-headers
cp "$TURSO_SRC/bindings/c/include/sqlite3.h" "$ROOT/Vendor/turso/include/"
cp "$TURSO_SRC/target/release/libturso_sqlite3.a" "$ROOT/Vendor/turso/lib/"
cp "$TURSO_SRC/target/release/libturso_sqlite3.dylib" "$ROOT/Vendor/turso/lib/" 2>/dev/null || true

# Keep Sources/CTursoSQLite3 headers in sync for the SPM C target.
mkdir -p "$ROOT/Sources/CTursoSQLite3/include"
cp "$ROOT/Vendor/turso/include/sqlite3.h" "$ROOT/Sources/CTursoSQLite3/include/"
printf '%s\n' 'module CTursoSQLite3 {' '  header "sqlite3.h"' '  export *' '}' \
  > "$ROOT/Sources/CTursoSQLite3/include/module.modulemap"

# Optional XCFramework for Xcode app targets.
mkdir -p /tmp/turso-headers
cp "$ROOT/Vendor/turso/include/sqlite3.h" /tmp/turso-headers/
printf '%s\n' 'module CTursoSQLite3 {' '  header "sqlite3.h"' '  export *' '}' \
  > /tmp/turso-headers/module.modulemap

rm -rf "$OUT_XCFRAMEWORK"
xcodebuild -create-xcframework \
  -library "$ROOT/Vendor/turso/lib/libturso_sqlite3.a" \
  -headers /tmp/turso-headers \
  -output "$OUT_XCFRAMEWORK"

echo "Wrote $OUT_XCFRAMEWORK and Sources/CTursoSQLite3/include"
