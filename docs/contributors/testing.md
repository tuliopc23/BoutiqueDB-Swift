# Testing (contributors)

This guide covers the validation gates to run before opening a pull request or tagging a release.

## Swift package tests

```bash
swift test
```

For local engine development:

```bash
./Scripts/build-turso-sdk-xcframework.sh
BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
```

## Platform build validation

```bash
swift build

xcodebuild -scheme BoutiqueDB-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation -skipMacroValidation \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
```

## Code quality

```bash
swift format lint --strict --recursive Sources Tests Package.swift
./Scripts/build-docs.sh
```

## Consumer example

```bash
cd Examples/Consumer
swift build -Xswiftc -warnings-as-errors
```

## CloudKit QA

Live CloudKit sync requires physical devices with a signed-in iCloud account. Follow the [CloudKit QA checklist](cloudkit-qa-checklist).

## Engine tests

If your PR changes the engine, run the engine test suites in `../BoutiqueDB`:

```bash
cd ../BoutiqueDB
cargo test
cargo fmt
cargo clippy --workspace --all-features --all-targets -- --deny=warnings
make -C sqlite/conformance run-rust ARGS='--snapshot-filter __never__'
```

## Pre-release gates

- [ ] `swift test` passes on macOS.
- [ ] iOS destination build succeeds.
- [ ] DocC documentation builds (`./Scripts/build-docs.sh`).
- [ ] `swift format lint` passes.
- [ ] Multi-arch `TursoSDK.xcframework` is built and validated.
- [ ] `Package.swift` checksum is updated if the binary changed.
