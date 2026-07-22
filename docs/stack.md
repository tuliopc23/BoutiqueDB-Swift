# Stack

BoutiqueDB is a thin, layered Swift package over a vendored Turso engine binary. The layers are intentionally narrow so that each can be replaced or tested in isolation.

```text
SwiftUI / @Observable models
        │
        ▼
BoutiqueDB (@MainActor)          ← open + migrate + LiveQuery host
   ├── DatabaseActor             ← serialized I/O (reads/writes)
   ├── concurrent DatabaseActor  ← optional MVCC writer (CDC ⊥ MVCC)
   ├── TursoStore                ← AsyncStream / generation invalidation
   └── SyncAdapter               ← CloudKit (default) or future adapters
        │
        ▼
TursoKit → CTursoSDK → libturso_sdk_kit  (sdk-kit / turso.h)
```

## Module responsibilities

| Product | Responsibility |
|--------|----------------|
| `BoutiqueDB` | High-level API, macros client, migrations, dependencies key, `@MainActor` container |
| `TursoKit` | Connections, statements, values, error mapping |
| `StructuredQueriesTurso` | `swift-structured-queries` driver + Turso DSL helpers (FTS, vector) |
| `TursoCKSync` | CDC ↔ `CKSyncEngine` record mapping and conflict handling |
| `TursoObservation` | Change streams and `TursoStore` invalidation |
| `BoutiqueDBMacros` | Swift compiler plugin for `@BoutiqueTable`, `@FTSIndex`, `@VectorIndex`, `@MaterializedView` |
| `CTursoSDK` | C module wrapping the `TursoSDK.xcframework` |

## Engine surface

BoutiqueDB opens the engine through Turso’s official language-binding C ABI (`sdk-kit`), not the limited `sqlite3` compatibility path. The primary C header is `sdk-kit/turso.h`.

Key capabilities exposed through `sdk-kit`:

- `async_io` for cooperative, non-blocking engine I/O.
- `experimental_features` as a comma-separated list of opt-in flags.
- Encryption cipher and key configuration at open time.
- Multi-process WAL coordination.

> **Warning:** The legacy `bindings/c` (`sqlite3.h`) path exists for compatibility but does not expose per-open feature flags or `async_io`. New code should use `sdk-kit`.

## Build and packaging

The Swift package distributes a multi-arch `TursoSDK.xcframework.zip` as a GitHub release asset. Maintainers rebuild it with:

```bash
./Scripts/build-turso-sdk-xcframework.sh
```

This produces binaries for macOS (arm64 + x86_64) and iOS (device arm64 + simulator arm64/x86_64). The package never uses `unsafeFlags` and is validated for Swift Package Index and App Store distribution.

## Concurrency model

- `BoutiqueDB` is `@MainActor` so it is safe to reference from SwiftUI.
- All engine I/O runs on a background `DatabaseActor` through `read`, `write`, and `writeConcurrent`.
- `TursoStore` publishes an `AsyncStream` of change events used by `LiveQuery`.
- `concurrentWrites` uses a separate connection with `BEGIN CONCURRENT` (MVCC) while keeping CDC on the primary handle.

See [Concurrency guide](guides/concurrency) and the [Architecture contributor doc](contributors/build-engine) for details.
