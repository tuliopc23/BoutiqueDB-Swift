# Publishing BoutiqueDB (SPI / GitHub)

## Checklist (public-ready)

- [x] `LICENSE` (MIT)
- [x] `NOTICE` (Turso + third-party)
- [x] Package icon (`Assets/BoutiqueDB.png`, `icon.png`)
- [x] `.spi.yml` (macOS first; iOS when multi-arch binary lands)
- [x] README install URL + platforms + products
- [x] `Package.swift` without `unsafeFlags` (binary `TursoSDK.xcframework`)
- [x] Public repo **BoutiqueDB-Swift** (`tuliopc23/BoutiqueDB-Swift`)
- [ ] Multi-arch xcframework (iOS device + sim) for solid SPI iOS builds
- [x] Release tag `v0.2.0` + GitHub Release asset zip
- [ ] SPI “Add a Package” (OAuth: https://swiftpackageindex.com/add-a-package)
- [ ] Prod docs polish pass

## Maintainer: build binary

```bash
# macos-arm64 (local + CI test)
SLICES=macos-arm64 ./Scripts/build-turso-sdk-xcframework.sh

# later: iOS slices when Rust targets ready
# SLICES=macos-arm64,ios-arm64,ios-arm64-simulator ./Scripts/build-turso-sdk-xcframework.sh

swift test
```

`Vendor/TursoSDK.xcframework` is gitignored by default (large). CI builds it; releases attach the zip.
`Package.swift` uses the release zip URL unless a local xcframework exists or `BOUTIQUE_LOCAL_TURSO_SDK=1`.

## Consumer install

```swift
.package(url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git", from: "0.2.0")
```

## Tag + binary release

```bash
# After CHANGELOG cut + local swift test
git tag -a v0.2.0 -m "BoutiqueDB 0.2.0"
git push public main --tags   # remote: BoutiqueDB-Swift

# Attach prebuilt zip (or let release.yml rebuild from engine monorepo)
gh release create v0.2.0 Vendor/TursoSDK.xcframework.zip \
  --repo tuliopc23/BoutiqueDB-Swift \
  --title "0.2.0" \
  --notes "See CHANGELOG.md"
```

Checksum in `Package.swift` must match:

```bash
swift package compute-checksum Vendor/TursoSDK.xcframework.zip
```

## SPI

1. Package resolves from a clean clone (no local `Vendor/*.xcframework`).
2. No `unsafeFlags`.
3. https://swiftpackageindex.com/add-a-package → `https://github.com/tuliopc23/BoutiqueDB-Swift`
4. Optional DocC once documentation targets build cleanly.
