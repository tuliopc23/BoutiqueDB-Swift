---
name: boutiquedb-contributing
description: |
  Guides engine and Swift package contributors through build, test, multi-arch packaging, SPI checklist, and releases.
  Use when the user asks about "build BoutiqueDB engine", "build TursoSDK", "multi-arch",
  "SPI checklist", "BoutiqueDB tests", or "BoutiqueDB release".
---

# BoutiqueDB contributing

Help maintainers and contributors build the engine, validate the Swift package, and ship releases for iOS and macOS.

## Trigger phrases

- "build BoutiqueDB engine"
- "build TursoSDK"
- "multi-arch xcframework"
- "SPI checklist BoutiqueDB"
- "BoutiqueDB release"
- "BoutiqueDB tests"

## Workflow

1. **Identify the repo**: `BoutiqueDB` for engine work, `BoutiqueDB-Swift` for the Swift package.
2. **Engine build** (in `BoutiqueDB`):
   ```bash
   cargo build -p turso_sdk_kit
   # Follow BoutiqueDB/AGENTS.md for full engine test suite
   ```
3. **Swift package build + test**:
   ```bash
   cd BoutiqueDB-Swift
   ./Scripts/build-turso-sdk-xcframework.sh   # default SLICES=all
   BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
   ```
   Single debug slice only for local debugging:
   ```bash
   SLICES=macos-arm64 ./Scripts/build-turso-sdk-xcframework.sh
   BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
   ```
   Never ship single-slice binaries.
4. **Multi-arch validation**:
   - Run `./Scripts/build-turso-sdk-xcframework.sh` (default `SLICES=all`).
   - Verify slices with `lipo -info` on every `.a`.
   - Confirm `Vendor/TursoSDK.xcframework` contains macOS, `ios-arm64`, and `ios-*-simulator` slices.
   - Update `Package.swift` `tursoSDKChecksum` if the binary changed.
5. **SPI / App Store checklist**:
   - No `unsafeFlags` in `Package.swift`.
   - Public repo, `LICENSE`, `README.md`, `.spi.yml` with macOS + iOS.
   - Multi-arch `TursoSDK.xcframework.zip` on the GitHub release asset matching tag `vX.Y.Z`.
   - Clean clone builds (`swift build`) and iOS simulator destination builds.
6. **Testing gates**:
   - `swift test` or `BOUTIQUE_LOCAL_TURSO_SDK=1 swift test`.
   - `swift format lint --strict --recursive Sources Tests Package.swift` if `swift-format` is configured.
   - `xcodebuild -scheme BoutiqueDB-Package -destination 'platform=iOS Simulator,name=iPhone 16' build`.
7. **Release**: bump `Package.swift` version/checksum, tag `vX.Y.Z`, build and attach `TursoSDK.xcframework.zip`.
8. **Reference docs**:
   - `docs/contributors/build-engine.md`
   - `docs/contributors/multi-arch-packaging.md`
   - `docs/contributors/spi-checklist.md`
   - `docs/contributors/testing.md`
   - `docs/contributors/publishing.md`
   - `BoutiqueDB/AGENTS.md`
