# Installation

BoutiqueDB is distributed as a Swift Package Manager (SPM) package. It supports iOS 17+ and macOS 14+.

## Requirements

- iOS 17.0+ or macOS 14.0+
- Swift 6.1+
- Xcode 16+
- For local engine builds: Rust toolchain and Xcode

## Add the package

### Swift Package Manager manifest

```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(
  name: "MyApp",
  dependencies: [
    .package(
      url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git",
      exact: "0.3.0-beta.1"
    ),
  ],
  targets: [
    .target(
      name: "MyApp",
      dependencies: [
        .product(name: "BoutiqueDB", package: "BoutiqueDB-Swift"),
      ]
    )
  ]
)
```

### Xcode

1. **File → Add Package Dependencies…**
2. Enter `https://github.com/tuliopc23/BoutiqueDB-Swift`
3. Select the `BoutiqueDB` product.

## Engine binary

The package depends on a `TursoSDK.xcframework.zip` release asset. By default, SPM downloads it from GitHub Releases. For local development with a custom engine build, set `BOUTIQUE_LOCAL_TURSO_SDK=1` and place `Vendor/TursoSDK.xcframework` in the package checkout:

```bash
# From the BoutiqueDB-Swift checkout
./Scripts/build-turso-sdk-xcframework.sh
BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
```

> **Warning:** Always ship full multi-arch binaries for App Store and SPI: macOS arm64 + x86_64, iOS device arm64, and iOS Simulator arm64/x86_64. Single-slice builds are only for local debugging.

## Import in source

```swift
import BoutiqueDB
import StructuredQueries
```

You only need `BoutiqueDB` for the high-level API. Import `StructuredQueries` when you define `@Table` models.
