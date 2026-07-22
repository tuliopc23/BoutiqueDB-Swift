#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYMBOLS="$ROOT/.build/out/symbolgraph"
MODULE_SYMBOLS="$ROOT/.build/BoutiqueDB-symbols"
ARCHIVE="$ROOT/.build/BoutiqueDB.doccarchive"

cd "$ROOT"
swift package dump-symbol-graph

rm -rf "$MODULE_SYMBOLS" "$ARCHIVE"
mkdir -p "$MODULE_SYMBOLS"
cp "$SYMBOLS/BoutiqueDB.symbols.json" "$MODULE_SYMBOLS/"
if [[ -f "$SYMBOLS/BoutiqueDB@Dependencies.symbols.json" ]]; then
  cp "$SYMBOLS/BoutiqueDB@Dependencies.symbols.json" "$MODULE_SYMBOLS/"
fi

xcrun docc convert Sources/BoutiqueDB/BoutiqueDB.docc \
  --additional-symbol-graph-dir "$MODULE_SYMBOLS" \
  --fallback-display-name BoutiqueDB \
  --fallback-bundle-identifier dev.tuliocunha.BoutiqueDB \
  --fallback-bundle-version 0.3.0-beta.1 \
  --output-path "$ARCHIVE" \
  --warnings-as-errors

echo "Built $ARCHIVE"
