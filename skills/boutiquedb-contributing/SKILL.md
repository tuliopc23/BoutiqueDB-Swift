---
name: boutiquedb-contributing
description: |
  Guides engine and Swift package contributors through build, test, multi-arch packaging, and SPI checklist.
  Use when the user asks about "build BoutiqueDB engine", "build TursoSDK", "multi-arch",
  "SPI checklist", "BoutiqueDB tests", or "BoutiqueDB release".
---

# BoutiqueDB contributing

Help maintainers and contributors build the engine, validate the Swift package, and ship releases.

## Trigger phrases

- "build BoutiqueDB engine"
- "build TursoSDK"
- "multi-arch xcframework"
- "SPI checklist BoutiqueDB"
- "BoutiqueDB release"
- "BoutiqueDB tests"

## Workflow

1. **Identify the repo**: `BoutiqueDB` for engine work, `BoutiqueDB-Swift` for the package.
2. **Engine build**:
   ```bash
   cd BoutiqueDB
   cargo build -p turso_sdk_kit --release
   TURSO_SDK_FEATURES=fts,encryption ./Scripts/build-turso-sdk-kit.sh
   ```
3. **Swift package build + test**:
   ```bash
   cd BoutiqueDB-Swift
   ./Scripts/build-turso-sdk-xcframework.sh
   BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
   ```
4. **Multi-arch validation**:
   - Run `./Scripts/build-turso-sdk-xcframework.sh` (default `SLICES=all`).
   - Verify slices with `lipo -info`.
   - Update `Package.swift` checksum if the binary changed.
5. **SPI/App Store checklist**:
   - No `unsafeFlags`.
   - Public repo, `LICENSE`, `README.md`, `.spi.yml` with macOS + iOS.
   - Multi-arch `TursoSDK.xcframework.zip` on the release.
   - Clean clone builds; iOS destination builds.
6. **Testing gates**:
   - `swift test`
   - `swift format lint --strict --recursive Sources Tests Package.swift`
   - `./Scripts/build-docs.sh`
   - `cd Examples/Consumer && swift build -Xswiftc -warnings-as-errors`
   - `xcodebuild -scheme BoutiqueDB-Package -destination 'platform=iOS Simulator,name=iPhone 16' build`
7. **Reference docs**:
   - `docs/contributors/build-engine.md`
   - `docs/contributors/multi-arch-packaging.md`
   - `docs/contributors/spi-checklist.md`
   - `docs/contributors/testing.md`
   - `docs/contributors/publishing.md`
   - `BoutiqueDB/AGENTS.md`
