# SPI multi-arch binary policy

**Always** produce and validate **iOS + macOS** engine binaries for public work.

```bash
./Scripts/build-turso-sdk-xcframework.sh   # default SLICES=all
```

Produces `Vendor/TursoSDK.xcframework` with:

- `macos-arm64_x86_64`
- `ios-arm64`
- `ios-arm64_x86_64-simulator`

Update `Package.swift` checksum after every shippable rebuild. See `AGENTS.md` and `docs/Publishing.md`.
