---
title: "Swift Package Index (SPI) Checklist"
sidebarTitle: "SPI Checklist"
description: "Validation requirements for publishing BoutiqueDB-Swift to the Swift Package Index."
---

Before releasing new versions or tagging releases for the **Swift Package Index (SPI)**, verify that all packaging requirements pass.

---

## Validation Checklist

<Steps>
  <Step title="No Unsafe Linker Flags">
    Ensure `Package.swift` contains no `unsafeFlags` or local hardcoded path linkers. Multi-arch binaries must use `binaryTarget(name: "TursoSDK", url: ..., checksum: ...)`.
  </Step>

  <Step title="Verify `.spi.yml` Targets">
    Check that `.spi.yml` builds both macOS and iOS targets:

    ```yaml .spi.yml
    version: 1
    builder:
      configs:
        - platform: macos-xcodebuild
        - platform: ios
    ```
  </Step>

  <Step title="Verify Multi-Arch XCFramework Slices">
    Run `lipo` inspection to ensure universal binaries are included:
    - `macos-arm64` + `macos-x86_64`
    - `ios-arm64`
    - `ios-arm64-simulator` + `ios-x86_64-simulator`
  </Step>

  <Step title="Clean Environment Xcode Build Test">
    Verify that clean machine clones resolve and build successfully:

    ```bash
    xcodebuild -scheme BoutiqueDB-Package -destination 'platform=iOS Simulator,name=iPhone 16' build
    ```
  </Step>

  <Step title="Public Repository & SPI Claim">
    The repo must be public before SPI can index it. Add it at
    https://swiftpackageindex.com/add-a-package with the GitHub URL.
  </Step>

  <Step title="GitHub Actions Billing">
    Confirm GitHub Actions billing is unlocked (`.github/workflows/swift.yml`).
    If builds fail immediately with a billing/lock message, resolve it in
    repository settings before release.
  </Step>
</Steps>
