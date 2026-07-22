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
- [x] Stable engine binary `v0.2.1` + zip asset + checksum in `Package.swift`
- [x] Production-beta package tag `v0.3.0-beta.1` (reuses verified v0.2.1 binary)
- [ ] SPI “Add a Package” OAuth (owner): https://swiftpackageindex.com/add-a-package
- [ ] GitHub Actions billing unlocked (hosted runners currently blocked on account)

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
.package(
  url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git",
  exact: "0.3.0-beta.1"
)
```

## Tag + release

Prerelease tags reuse the already verified binary version declared in
`Package.swift`; the release workflow runs source, test, DocC, consumer, and iOS
gates before creating a GitHub prerelease. Stable tags rebuild and attach a new
full multi-architecture engine archive.

```bash
git tag -a v0.3.0-beta.1 -m "BoutiqueDB 0.3.0-beta.1"
git push public main v0.3.0-beta.1
```

## SPI

1. Clean clone resolves (no local Vendor binary → URL binaryTarget).
2. No `unsafeFlags`.
3. https://swiftpackageindex.com/add-a-package → `https://github.com/tuliopc23/BoutiqueDB-Swift`
4. Expect macOS + iOS platform badges after first index.

## GitHub Actions note

If Actions jobs fail immediately with *account is locked due to a billing issue*,
that is a **hosting/billing lock**, not a package defect. Local gates before push:

```bash
swift build -Xswiftc -warnings-as-errors
swift test
swift format lint --strict --recursive Sources Tests Package.swift
./Scripts/build-docs.sh
(cd Examples/Consumer && swift build -Xswiftc -warnings-as-errors)
xcodebuild -scheme BoutiqueDB-Package \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation -skipMacroValidation \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
```
