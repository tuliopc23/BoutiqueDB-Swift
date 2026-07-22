#!/usr/bin/env bash
# Build TursoSDK.xcframework from turso_sdk_kit (official language-binding C ABI).
#
# PERMANENT DEFAULT — full SPI / App Store set (macOS + iOS device + iOS Simulator):
#   macos-arm64, macos-x86_64, ios-arm64, ios-arm64-simulator, ios-x86_64-simulator
#
# macOS arm64+x86_64 are lipo'd into one macos slice.
# iOS Simulator arm64+x86_64 are lipo'd into one simulator slice.
#
# Usage:
#   ./Scripts/build-turso-sdk-xcframework.sh              # ALWAYS full multi-arch
#   SLICES=all ./Scripts/build-turso-sdk-xcframework.sh   # same
#   SLICES=macos-arm64 ./Scripts/build-turso-sdk-xcframework.sh  # local debug ONLY
#
# Requires: rustup (PATH: ~/.cargo/bin first), Apple SDKs, xcodebuild.
#
set -euo pipefail

export PATH="${HOME}/.cargo/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TURSO_SRC="${TURSO_SRC:-$ROOT/../BoutiqueDB}"
if [[ ! -d "$TURSO_SRC/sdk-kit" ]]; then
  echo "Turso engine with sdk-kit not found at $TURSO_SRC" >&2
  exit 1
fi

FEATURES="${TURSO_SDK_FEATURES:-fts,encryption,pure-rust-crypto}"
DEFAULT_SLICES="macos-arm64,macos-x86_64,ios-arm64,ios-arm64-simulator,ios-x86_64-simulator"
SLICES_RAW="${SLICES:-all}"
case "$SLICES_RAW" in
  all|spi|full) SLICES="$DEFAULT_SLICES" ;;
  *) SLICES="$SLICES_RAW" ;;
esac

OUT_XCFW="$ROOT/Vendor/TursoSDK.xcframework"
BUILD_ROOT="$ROOT/.build/turso-xcframework"
HEADERS="$BUILD_ROOT/headers"
MACOS_MIN="${MACOS_DEPLOYMENT_TARGET:-14.0}"
IOS_MIN="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
# Reuse engine target/ by default (faster incremental). Set ISOLATED_CARGO=1 to use BUILD_ROOT/cargo.
ISOLATED_CARGO="${ISOLATED_CARGO:-0}"

rm -rf "$BUILD_ROOT" "$OUT_XCFW"
mkdir -p "$HEADERS"
cp "$TURSO_SRC/sdk-kit/turso.h" "$HEADERS/"
cat > "$HEADERS/module.modulemap" <<'MM'
module TursoSDK {
  header "turso.h"
  export *
}
MM

mkdir -p "$ROOT/Sources/CTursoSDK/include"
cp "$TURSO_SRC/sdk-kit/turso.h" "$ROOT/Sources/CTursoSDK/include/"
printf '%s\n' 'module CTursoSDK {' '  header "turso.h"' '  export *' '}' \
  > "$ROOT/Sources/CTursoSDK/include/module.modulemap"

echo "cargo:    $(command -v cargo) ($(cargo -V 2>/dev/null || true))"
echo "features: $FEATURES"
echo "slices:   $SLICES"
echo "mins:     macOS ${MACOS_MIN} / iOS ${IOS_MIN}"

ensure_rust_target() {
  local triple="$1"
  if ! rustup target list --installed 2>/dev/null | grep -qx "$triple"; then
    echo "Installing rustup target $triple …"
    rustup target add "$triple"
  fi
}

create_slice() {
  local slice="$1"
  local triple sdk_name rustflags

  case "$slice" in
    macos-arm64)
      triple="aarch64-apple-darwin"
      sdk_name="macosx"
      rustflags="-C link-arg=-mmacosx-version-min=${MACOS_MIN}"
      ;;
    macos-x86_64)
      triple="x86_64-apple-darwin"
      sdk_name="macosx"
      rustflags="-C link-arg=-mmacosx-version-min=${MACOS_MIN}"
      ;;
    ios-arm64)
      triple="aarch64-apple-ios"
      sdk_name="iphoneos"
      rustflags="-C link-arg=-miphoneos-version-min=${IOS_MIN}"
      ;;
    ios-arm64-simulator)
      triple="aarch64-apple-ios-sim"
      sdk_name="iphonesimulator"
      rustflags="-C link-arg=-mios-simulator-version-min=${IOS_MIN}"
      ;;
    ios-x86_64-simulator)
      triple="x86_64-apple-ios"
      sdk_name="iphonesimulator"
      rustflags="-C link-arg=-mios-simulator-version-min=${IOS_MIN}"
      ;;
    *)
      echo "Unknown slice: $slice" >&2
      exit 1
      ;;
  esac

  ensure_rust_target "$triple"

  local sdk
  sdk="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
  local out_dir="$BUILD_ROOT/$slice"
  mkdir -p "$out_dir"

  local cargo_target_dir="$TURSO_SRC/target"
  if [[ "$ISOLATED_CARGO" == "1" ]]; then
    cargo_target_dir="$BUILD_ROOT/cargo/$slice"
  fi

  echo "==> Building turso_sdk_kit for $slice ($triple)"
  echo "    SDKROOT=$sdk"
  echo "    CARGO_TARGET_DIR=$cargo_target_dir"
  (
    cd "$TURSO_SRC"
    env \
      SDKROOT="$sdk" \
      CARGO_TARGET_DIR="$cargo_target_dir" \
      MACOSX_DEPLOYMENT_TARGET="${MACOS_MIN}" \
      IPHONEOS_DEPLOYMENT_TARGET="${IOS_MIN}" \
      CARGO_TARGET_AARCH64_APPLE_IOS_RUSTFLAGS="$rustflags" \
      CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS="$rustflags" \
      CARGO_TARGET_X86_64_APPLE_IOS_RUSTFLAGS="$rustflags" \
      CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS="$rustflags" \
      CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS="$rustflags" \
      RUSTFLAGS="${RUSTFLAGS:-} ${rustflags}" \
      cargo rustc -p turso_sdk_kit --release --features "$FEATURES" \
        --target "$triple" \
        --crate-type=staticlib
  )

  local lib="$cargo_target_dir/$triple/release/libturso_sdk_kit.a"
  if [[ ! -f "$lib" ]]; then
    echo "lib not found for $slice at $lib" >&2
    exit 1
  fi
  cp "$lib" "$out_dir/libturso_sdk_kit.a"
  lipo -info "$out_dir/libturso_sdk_kit.a" || true
  echo "    ok: $out_dir/libturso_sdk_kit.a"
}

# --- Build atomic slices ---
BUILT=()
IFS=',' read -ra SLICE_ARR <<< "$SLICES"
for s in "${SLICE_ARR[@]}"; do
  s="$(echo "$s" | tr -d ' ')"
  [[ -z "$s" ]] && continue
  create_slice "$s"
  BUILT+=("$s")
done

# --- macOS universal ---
MAC_UNIV=""
if [[ -f "$BUILD_ROOT/macos-arm64/libturso_sdk_kit.a" && -f "$BUILD_ROOT/macos-x86_64/libturso_sdk_kit.a" ]]; then
  mkdir -p "$BUILD_ROOT/macos-universal"
  lipo -create \
    "$BUILD_ROOT/macos-arm64/libturso_sdk_kit.a" \
    "$BUILD_ROOT/macos-x86_64/libturso_sdk_kit.a" \
    -output "$BUILD_ROOT/macos-universal/libturso_sdk_kit.a"
  lipo -info "$BUILD_ROOT/macos-universal/libturso_sdk_kit.a"
  MAC_UNIV="$BUILD_ROOT/macos-universal/libturso_sdk_kit.a"
elif [[ -f "$BUILD_ROOT/macos-arm64/libturso_sdk_kit.a" ]]; then
  MAC_UNIV="$BUILD_ROOT/macos-arm64/libturso_sdk_kit.a"
elif [[ -f "$BUILD_ROOT/macos-x86_64/libturso_sdk_kit.a" ]]; then
  MAC_UNIV="$BUILD_ROOT/macos-x86_64/libturso_sdk_kit.a"
fi

# --- iOS Simulator universal ---
SIM_UNIV=""
if [[ -f "$BUILD_ROOT/ios-arm64-simulator/libturso_sdk_kit.a" && -f "$BUILD_ROOT/ios-x86_64-simulator/libturso_sdk_kit.a" ]]; then
  mkdir -p "$BUILD_ROOT/ios-simulator-universal"
  lipo -create \
    "$BUILD_ROOT/ios-arm64-simulator/libturso_sdk_kit.a" \
    "$BUILD_ROOT/ios-x86_64-simulator/libturso_sdk_kit.a" \
    -output "$BUILD_ROOT/ios-simulator-universal/libturso_sdk_kit.a"
  lipo -info "$BUILD_ROOT/ios-simulator-universal/libturso_sdk_kit.a"
  SIM_UNIV="$BUILD_ROOT/ios-simulator-universal/libturso_sdk_kit.a"
elif [[ -f "$BUILD_ROOT/ios-arm64-simulator/libturso_sdk_kit.a" ]]; then
  SIM_UNIV="$BUILD_ROOT/ios-arm64-simulator/libturso_sdk_kit.a"
elif [[ -f "$BUILD_ROOT/ios-x86_64-simulator/libturso_sdk_kit.a" ]]; then
  SIM_UNIV="$BUILD_ROOT/ios-x86_64-simulator/libturso_sdk_kit.a"
fi

# --- Assemble xcframework ---
XCFW_ARGS=()
if [[ -n "$MAC_UNIV" ]]; then
  XCFW_ARGS+=(-library "$MAC_UNIV" -headers "$HEADERS")
fi
if [[ -f "$BUILD_ROOT/ios-arm64/libturso_sdk_kit.a" ]]; then
  XCFW_ARGS+=(-library "$BUILD_ROOT/ios-arm64/libturso_sdk_kit.a" -headers "$HEADERS")
fi
if [[ -n "$SIM_UNIV" ]]; then
  XCFW_ARGS+=(-library "$SIM_UNIV" -headers "$HEADERS")
fi

if [[ ${#XCFW_ARGS[@]} -eq 0 ]]; then
  echo "No libraries produced for xcframework" >&2
  exit 1
fi

echo "==> Creating $OUT_XCFW"
xcodebuild -create-xcframework "${XCFW_ARGS[@]}" -output "$OUT_XCFW"

echo "==> xcframework slices:"
find "$OUT_XCFW" -name "*.a" -print -exec lipo -info {} \;
echo "==> layout:"
find "$OUT_XCFW" -type d -maxdepth 2 | sort

# Require iOS device + at least one macOS/sim for SPI-ready builds when SLICES=all
if [[ "$SLICES_RAW" == "all" || "$SLICES_RAW" == "spi" || "$SLICES_RAW" == "full" || -z "${SLICES:-}" ]]; then
  if ! find "$OUT_XCFW" -type d -name 'ios-arm64' | grep -q .; then
    echo "SPI full build missing ios-arm64 slice" >&2
    exit 1
  fi
  if ! find "$OUT_XCFW" -type d \( -name 'macos-*' -o -name 'ios-*-simulator' \) | grep -q .; then
    echo "SPI full build missing macOS or iOS Simulator slice" >&2
    exit 1
  fi
fi

ZIP="$ROOT/Vendor/TursoSDK.xcframework.zip"
rm -f "$ZIP"
(
  cd "$ROOT/Vendor"
  ditto -c -k --sequesterRsrc --keepParent "TursoSDK.xcframework" "TursoSDK.xcframework.zip"
)

echo "==> Checksum"
SUM="$(swift package compute-checksum "$ZIP")"
echo "$SUM" | tee "$ROOT/Vendor/TursoSDK.xcframework.checksum"
echo "Wrote $OUT_XCFW and $ZIP"
echo "Update Package.swift tursoSDKChecksum to: $SUM"
ls -lh "$ZIP"
echo "Built slices: ${BUILT[*]}"
