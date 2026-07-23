---
title: "Building the Engine"
sidebarTitle: "Building the Engine"
description: "Instructions for building the Rust engine binary (libturso_sdk_kit) and multi-arch XCFramework."
---

While consumer developers integrate BoutiqueDB as a precompiled Swift package, contributors modifying the underlying Rust engine can rebuild `TursoSDK.xcframework` using provided build scripts.

---

## Prerequisites

- macOS 14.0+ with Xcode 15+
- Rust toolchain (`rustup` with `aarch64-apple-darwin`, `x86_64-apple-darwin`, `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios` targets installed).

---

## Build Execution

Run the universal multi-arch packaging script from the repository root:

```bash
# Build XCFramework containing macOS and iOS (Device + Simulator) slices
./Scripts/build-turso-sdk-xcframework.sh
```

<Note>
**Local Single-Slice Debugging**: For faster iteration during local debugging on Apple Silicon Macs, build a single slice using `SLICES=macos-arm64 ./Scripts/build-turso-sdk-xcframework.sh`.
</Note>

---

## Verification & Checksum Update

1. Verify XCFramework architecture slices:
   ```bash
   lipo -info Vendor/TursoSDK.xcframework/macos-arm64_x86_64/libturso_sdk_kit.a
   ```
2. Recompute zip checksum for `Package.swift`:
   ```bash
   swift package compute-checksum Vendor/TursoSDK.xcframework.zip
   ```
