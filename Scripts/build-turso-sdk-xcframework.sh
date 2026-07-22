#!/usr/bin/env bash
# Build TursoSDK.xcframework from turso_sdk_kit (official language-binding C ABI).
#
# Slices (expand over time):
#   - macos-arm64 (required for local + CI test)
#   - ios-arm64, ios-arm64-simulator (required before claiming iOS on SPI)
#
# Usage:
#   ./Scripts/build-turso-sdk-xcframework.sh
#   TURSO_SRC=../BoutiqueDB SLICES=macos-arm64 ./Scripts/build-turso-sdk-xcframework.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TURSO_SRC="${TURSO_SRC:-$ROOT/../BoutiqueDB}"
if [[ ! -d "$TURSO_SRC/sdk-kit" ]]; then
  echo "Turso engine with sdk-kit not found at $TURSO_SRC" >&2
  exit 1
fi

FEATURES="${TURSO_SDK_FEATURES:-fts,encryption}"
SLICES="${SLICES:-macos-arm64}"
OUT_XCFW="$ROOT/Vendor/TursoSDK.xcframework"
BUILD_ROOT="$ROOT/.build/turso-xcframework"
HEADERS="$BUILD_ROOT/headers"

rm -rf "$BUILD_ROOT" "$OUT_XCFW"
mkdir -p "$HEADERS"
cp "$TURSO_SRC/sdk-kit/turso.h" "$HEADERS/"
# module map for clang module consumers of the binary
cat > "$HEADERS/module.modulemap" <<'MM'
module TursoSDK {
  header "turso.h"
  export *
}
MM

# Also keep Sources/CTursoSDK headers in sync
mkdir -p "$ROOT/Sources/CTursoSDK/include"
cp "$TURSO_SRC/sdk-kit/turso.h" "$ROOT/Sources/CTursoSDK/include/"
printf '%s\n' 'module CTursoSDK {' '  header "turso.h"' '  export *' '}' \
  > "$ROOT/Sources/CTursoSDK/include/module.modulemap"

create_slice() {
  local slice="$1"
  local triple=""
  local sdk=""
  local min_flag=""
  case "$slice" in
    macos-arm64)
      triple="aarch64-apple-darwin"
      sdk="$(xcrun --sdk macosx --show-sdk-path)"
      min_flag="-mmacosx-version-min=14.0"
      ;;
    ios-arm64)
      triple="aarch64-apple-ios"
      sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
      min_flag="-miphoneos-version-min=17.0"
      ;;
    ios-arm64-simulator)
      triple="aarch64-apple-ios-sim"
      sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
      min_flag="-mios-simulator-version-min=17.0"
      ;;
    *)
      echo "Unknown slice: $slice" >&2
      exit 1
      ;;
  esac

  local out_dir="$BUILD_ROOT/$slice"
  mkdir -p "$out_dir"
  echo "==> Building turso_sdk_kit for $slice ($triple)"
  (
    cd "$TURSO_SRC"
    export SDKROOT="$sdk"
    # shellcheck disable=SC2086
    cargo rustc -p turso_sdk_kit --release --features "$FEATURES" \
      --target "$triple" \
      --crate-type=staticlib \
      -- $min_flag
  )

  local lib_candidates=(
    "$TURSO_SRC/target/$triple/release/libturso_sdk_kit.a"
    "$TURSO_SRC/target/release/libturso_sdk_kit.a"
  )
  local lib=""
  for c in "${lib_candidates[@]}"; do
    if [[ -f "$c" ]]; then lib="$c"; break; fi
  done
  if [[ -z "$lib" ]]; then
    echo "lib not found for $slice" >&2
    ls -la "$TURSO_SRC/target/$triple/release/" 2>/dev/null || true
    exit 1
  fi
  cp "$lib" "$out_dir/libturso_sdk_kit.a"
  echo "    $lib -> $out_dir/libturso_sdk_kit.a"
}

XCFW_ARGS=()
IFS=',' read -ra SLICE_ARR <<< "$SLICES"
for s in "${SLICE_ARR[@]}"; do
  s="$(echo "$s" | tr -d ' ')"
  create_slice "$s"
  XCFW_ARGS+=(-library "$BUILD_ROOT/$s/libturso_sdk_kit.a" -headers "$HEADERS")
done

echo "==> Creating $OUT_XCFW"
# shellcheck disable=SC2068
xcodebuild -create-xcframework ${XCFW_ARGS[@]} -output "$OUT_XCFW"

ZIP="$ROOT/Vendor/TursoSDK.xcframework.zip"
rm -f "$ZIP"
(
  cd "$ROOT/Vendor"
  zip -qry "TursoSDK.xcframework.zip" "TursoSDK.xcframework"
)

echo "==> Checksum"
swift package compute-checksum "$ZIP" | tee "$ROOT/Vendor/TursoSDK.xcframework.checksum"
echo "Wrote $OUT_XCFW and $ZIP"
