# SPI checklist

This checklist ensures BoutiqueDB can be indexed and built by the Swift Package Index and submitted to the App Store.

## Package manifest

- [ ] `Package.swift` has no `unsafeFlags`.
- [ ] `Package.swift` uses a `binaryTarget` for `TursoSDK` (URL or local path).
- [ ] `Package.swift` products are declared for `BoutiqueDB`, `TursoKit`, `StructuredQueriesTurso`, `TursoCKSync`, and `TursoObservation`.
- [ ] `Package.swift` declares `swift-tools-version:6.1` or later.
- [ ] `Package.swift` checksum matches the published `TursoSDK.xcframework.zip`.

## Repository

- [ ] Public GitHub repository.
- [ ] `LICENSE` file (MIT).
- [ ] `README.md` with install URL and platform badges.
- [ ] `.spi.yml` includes `macos-xcodebuild` and `ios` platform targets.

## Binary

- [ ] `TursoSDK.xcframework.zip` on the matching GitHub Release.
- [ ] macOS universal slice (arm64 + x86_64).
- [ ] iOS device arm64 slice.
- [ ] iOS Simulator universal slice (arm64 + x86_64).
- [ ] Clean clone builds on macOS without local `Vendor/TursoSDK.xcframework`.
- [ ] iOS destination build succeeds (`xcodebuild` or `swift build` with iOS SDK).

## Validation commands

```bash
swift build
xcodebuild -scheme BoutiqueDB-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation -skipMacroValidation \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
```

## App Store

- [ ] No `unsafeFlags`.
- [ ] No embedded multi-arch `.a` files committed to git.
- [ ] Binary slices are correct for the target platform.

See also [Multi-arch packaging](multi-arch-packaging) and [Publishing](publishing).
