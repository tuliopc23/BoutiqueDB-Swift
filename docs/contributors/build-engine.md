# Build the engine

The Swift package consumes a prebuilt `TursoSDK.xcframework` by default. To iterate on the engine itself, build from the `BoutiqueDB` source.

## Repository layout

- `BoutiqueDB` — engine monorepo (this repo’s sibling).
- `BoutiqueDB-Swift` — Swift package.

The Swift package’s `TURSO_SRC` defaults to `../BoutiqueDB`.

## Build the sdk-kit static library

```bash
cd ../BoutiqueDB
cargo build -p turso_sdk_kit --release
```

For optional features, enable Cargo features:

```bash
TURSO_SDK_FEATURES=fts,encryption ./Scripts/build-turso-sdk-kit.sh
```

## Build the xcframework

From the Swift package checkout:

```bash
./Scripts/build-turso-sdk-xcframework.sh
```

This builds the full multi-arch set by default:

- `macos-arm64_x86_64`
- `ios-arm64`
- `ios-arm64_x86_64-simulator`

Use `SLICES=macos-arm64` only for local debugging.

## Test with the local binary

```bash
BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
```

## Engine test gates

Before integrating a new engine build, run the upstream engine test suites in the `BoutiqueDB` repo:

```bash
cargo test
make test
make -C sqlite/conformance run-rust ARGS='--snapshot-filter __never__'
```

See `BoutiqueDB/AGENTS.md` for full engine contribution guidelines.

## Clean up

`Vendor/TursoSDK.xcframework` is gitignored. Remove it or rebuild as needed. Never commit multi-hundred-megabyte binaries.
