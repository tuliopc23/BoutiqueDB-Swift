# Multi-arch packaging

Public and Swift Package Index (SPI) releases of BoutiqueDB must include a universal, multi-arch `TursoSDK.xcframework`. Single-slice builds are only for local debugging.

## Required slices

| Slice | Architectures | Use |
|-------|---------------|-----|
| macOS | arm64 + x86_64 (universal) | Mac App Store and direct distribution |
| iOS device | arm64 | Physical iPhones and iPads |
| iOS Simulator | arm64 + x86_64 (universal) | Simulator testing, including Rosetta |

## Build the framework

```bash
# Default: full multi-arch
./Scripts/build-turso-sdk-xcframework.sh

# Debug single slice only — never ship this
SLICES=macos-arm64 ./Scripts/build-turso-sdk-xcframework.sh
```

The script produces `Vendor/TursoSDK.xcframework` and `Vendor/TursoSDK.xcframework.zip`.

## Validate slices

```bash
lipo -info Vendor/TursoSDK.xcframework/macos-*/*.a
lipo -info Vendor/TursoSDK.xcframework/ios-arm64*/*.a
```

Every `.a` must contain the expected architectures before the build is shipped.

## Update Package.swift

```bash
swift package compute-checksum Vendor/TursoSDK.xcframework.zip
```

Copy the checksum into `Package.swift` as `tursoSDKChecksum`. If you are releasing a new binary, also bump `tursoSDKVersion` and upload the zip to GitHub Releases with a matching tag.

## Security

- Do not commit `Vendor/TursoSDK.xcframework` or `.a` files to git (they are gitignored).
- Do not use `unsafeFlags` in `Package.swift`; SPI and App Store submission reject them.
- Store release signing identities and checksums in a safe location.

## CI validation

Before tagging, validate a clean clone:

```bash
rm -rf Vendor/TursoSDK.xcframework
swift build
xcodebuild -scheme BoutiqueDB-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```
