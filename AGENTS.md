# BoutiqueDB-Swift — Agent Guidelines

Swift package: local-first persistence on Turso (sdk-kit), LiveQuery, CloudKit.


## Scope (Swift only)

This package is for **Swift / Apple apps** (iOS + macOS) via SPM / SPI only.

- **Do not** add .NET, Java, Python, Go, npm, crates.io, or other registry publish workflows.
- **Do not** mirror upstream Turso multi-language binding CI into this repo.
- Engine monorepo (`BoutiqueDB`) is a private build input for `sdk-kit`; product surface is this Swift package.

## Permanent packaging rule (SPI / App Store)

**Always ship and validate both iOS and macOS.** Do not treat macOS-only
binaries as “done” for public package or SPI work.

| Platform | Minimum | Binary slice(s) required |
|----------|---------|---------------------------|
| **macOS** | 14.0 | `macos-arm64` + `macos-x86_64` (lipo universal) |
| **iOS device** | 17.0 | `ios-arm64` |
| **iOS Simulator** | 17.0 | `ios-arm64-simulator` + `ios-x86_64-simulator` (lipo) |

Default engine build:

```bash
# ALWAYS full multi-arch unless debugging a single slice
./Scripts/build-turso-sdk-xcframework.sh
# equivalent:
SLICES=all ./Scripts/build-turso-sdk-xcframework.sh
```

Narrow slices **only** for a local debug loop (never for release, SPI, or
`Package.swift` checksum updates):

```bash
SLICES=macos-arm64 ./Scripts/build-turso-sdk-xcframework.sh
```

After any binary rebuild that will ship:

1. `swift package compute-checksum Vendor/TursoSDK.xcframework.zip`
2. Update `tursoSDKChecksum` (+ version if releasing) in `Package.swift`
3. Confirm `Vendor/TursoSDK.xcframework` contains **macos**, **ios-arm64**, and **ios-*-simulator**
4. `lipo -info` every `.a` under the xcframework
5. Release asset URL must match tag (`vX.Y.Z`)

## SPI checklist

- [ ] No `unsafeFlags` in `Package.swift`
- [ ] Public GitHub repo, LICENSE, README install URL
- [ ] `.spi.yml` includes **macos-xcodebuild** and **ios**
- [ ] Multi-arch `TursoSDK.xcframework.zip` on the release
- [ ] Clean clone (no local Vendor binary) resolves + builds on macOS
- [ ] iOS destination build succeeds (device or simulator)

```bash
# Clean-machine style (URL binary)
rm -rf Vendor/TursoSDK.xcframework   # or fresh clone
swift build
# iOS (simulator)
xcodebuild -scheme BoutiqueDB-Package -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Engine source

`TURSO_SRC` defaults to `../BoutiqueDB`. Uses **sdk-kit** (`turso.h` /
`libturso_sdk_kit`), not bindings/c.

Prefer rustup cargo (`~/.cargo/bin` before Homebrew) so the engine
`rust-toolchain.toml` is honoured.

## Tests

```bash
# Local with path binary
BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
# or just swift test when Vendor/TursoSDK.xcframework exists
swift test
```

## Commit style

```text
[scope: ]<imperative summary>

<why>

Tests: <what you ran>
```

Example: `package: ship multi-arch TursoSDK for SPI iOS+macOS`.

## Do not

- Ship SPI/public releases with only `macos-arm64`
- Commit multi-hundred-MB `Vendor/*.xcframework` or `.a` (gitignored; use Releases)
- Reintroduce linker `unsafeFlags` for distribution
- Assume iOS works because macOS tests passed — always build an iOS destination
