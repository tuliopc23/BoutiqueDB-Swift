# Publishing BoutiqueDB (SPI / GitHub)

## Permanent rule: iOS + macOS

Public / SPI releases **must** include a multi-arch `TursoSDK.xcframework`:

| Slice | Architectures |
|-------|----------------|
| macOS | arm64 + x86_64 (universal) |
| iOS device | arm64 |
| iOS Simulator | arm64 + x86_64 (universal) |

Never ship macOS-only binaries for SPI. See `AGENTS.md`.

## Checklist

- [x] `LICENSE` (MIT), `NOTICE`
- [x] Package icon (`Assets/BoutiqueDB.png`, `icon.png`)
- [x] `.spi.yml` — **macos-xcodebuild** + **ios**
- [x] `Package.swift` without `unsafeFlags` (binary `TursoSDK`)
- [x] Public repo [BoutiqueDB-Swift](https://github.com/tuliopc23/BoutiqueDB-Swift)
- [x] Multi-arch xcframework (macOS + iOS device + Simulator)
- [x] Release `v0.2.1` + zip asset + checksum in `Package.swift`
- [ ] SPI “Add a Package” OAuth (owner): https://swiftpackageindex.com/add-a-package

## Build binary

```bash
# Full SPI set (default — do this for every public release)
./Scripts/build-turso-sdk-xcframework.sh

# Update Package.swift with printed checksum
swift package compute-checksum Vendor/TursoSDK.xcframework.zip
```

`Vendor/TursoSDK.xcframework` is gitignored. CI and releases attach/build the zip.

## Consumer install

```swift
.package(url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git", from: "0.2.1")
```

## Tag + release

```bash
git tag -a v0.2.1 -m "BoutiqueDB 0.2.1"
git push public main --tags

# Prefer attaching the local multi-arch zip (CI also builds SLICES=all):
gh release create v0.2.1 Vendor/TursoSDK.xcframework.zip \
  --repo tuliopc23/BoutiqueDB-Swift \
  --title "0.2.1" \
  --notes "See CHANGELOG.md"
```

## SPI

1. Clean clone resolves (no local Vendor binary → URL binaryTarget).
2. No `unsafeFlags`.
3. https://swiftpackageindex.com/add-a-package → `https://github.com/tuliopc23/BoutiqueDB-Swift`
4. Expect macOS + iOS platform badges after first index.
