---
title: "Installation"
sidebarTitle: "Installation"
description: "How to add BoutiqueDB to your iOS and macOS Swift projects using Swift Package Manager."
---

## Swift Package Manager (SPM)

BoutiqueDB supports **iOS 17.0+** and **macOS 14.0+**. You can install it directly via Xcode or inside `Package.swift`.

### Xcode Integration

1. Open your project in Xcode.
2. Navigate to **File > Add Package Dependencies...**
3. Enter the repository URL:
   ```text
   https://github.com/tuliopc23/BoutiqueDB-Swift
   ```
4. Select **Up to Next Major Version** starting from `0.3.0-beta.1` (or the latest git tag).
5. Choose your target and click **Add Package**.

---

### Package.swift Integration

Add `BoutiqueDB-Swift` to your `Package.swift` dependencies array:

```swift Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git", from: "0.3.0-beta.1")
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "BoutiqueDB", package: "BoutiqueDB-Swift")
            ]
        )
    ]
)
```

---

<Note>
**Multi-Arch XCFramework Binary**: `BoutiqueDB` includes a precompiled static framework (`TursoSDK.xcframework`) containing universal binaries for `macos-arm64`, `macos-x86_64`, `ios-arm64`, and `ios-simulator`. No local Rust toolchain or build setup is required for consumers!
</Note>

---

## Verifying Your Setup

Add a quick test to your app delegate or main app initialization to verify BoutiqueDB can create a database instance:

```swift
import BoutiqueDB

@main
struct MyApp: App {
    init() {
        do {
            let db = try BoutiqueDB.open(url: BoutiqueDB.inMemoryURL())
            print("Successfully initialized BoutiqueDB instance: \(db)")
        } catch {
            print("Failed to initialize BoutiqueDB: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```
