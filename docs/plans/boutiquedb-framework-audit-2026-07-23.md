# BoutiqueDB Framework Audit & Enhancement Plan

## Goal

Audit BoutiqueDB-Swift across Swift 6 concurrency, public API ergonomics, Turso-only engine feature integration, SwiftUI observation / CloudKit sync, and Apple-ecosystem packaging/DX. Produce a severity-ranked findings list and a concrete enhancement roadmap so the framework is safe under strict concurrency, exposes Turso capabilities idiomatically, and is SPI / App Store ready.

## Background

- The package is layered as `CTursoSDK` → `TursoKit` → `StructuredQueriesTurso` → `TursoObservation` / `TursoCKSync` → `BoutiqueDB` (umbrella) + `BoutiqueDBMacros`.
- Current maturity is roughly **85% ready for internal dogfooding** and **55% ready for SPI/public release**; live CloudKit validation and iOS multi-arch packaging are the largest remaining risks.
- Core pieces are built: `BoutiqueDB.read/write`, `BoutiqueDB.open`, `@LiveQuery/@LiveQueryOne`, `BoutiqueDBSyncEngine`, `TursoCKSyncEngine`, `@BoutiqueTable/@FTSIndex/@VectorIndex`, and `TursoCapabilities` probing.
- Several design docs (`BoutiqueDB-Design.md`, `BoutiqueDB-TursoFeatures.md`) still describe the older `bindings/c` / `libturso_sqlite3` path, while `Package.swift` and the code now use the `sdk-kit` `turso.h` ABI.
- External research confirms the `sdk-kit` C ABI exposes most experimental features (`views`, `index_method`, `encryption`, `multiprocess_wal`, `attach`, etc.) through `turso_database_config_t`, but it does **not** expose `sqlite3_update_hook` or a CDC push callback. SQLiteData and GRDB suggest `AsyncStream`/`ValueObservation`, task-cancellation rollback, and `DatabaseQueue`/`DatabasePool`-style connection abstractions.

## Approach

1. Treat the source of truth as the actual code in `Sources/` and `Package.swift`, not the markdown docs, because several docs are stale or aspirational.
2. Work in priority order: Swift 6 concurrency & SPI blockers first; then observation / CloudKit sync lifecycle; then Turso feature DSL / docs; then DX examples.
3. Prefer small, test-driven changes that keep the public API stable; break API only where the current surface is unsafe or undocumented.
4. Validate with `BOUTIQUE_LOCAL_TURSO_SDK=1 swift test`, iOS simulator build (`xcodebuild -scheme BoutiqueDB-Package -destination 'platform=iOS Simulator,name=iPhone 16' build`), and eventually live CloudKit device testing.

## Work Items

### 1. Swift 6 concurrency & public API safety

| # | Severity | Finding | File:line | Action |
|---|----------|---------|-----------|--------|
| 1.1 | Critical | `TursoConnection` uses `@unchecked Sendable` with a manual `NSRecursiveLock`. | `Sources/TursoKit/TursoConnection.swift:16` | Convert `TursoConnection` to an actor; make the public low-level API `async` or expose `nonisolated` read-only helpers and `async` mutation methods. |
| 1.2 | Critical | `TursoDatabase` uses `@unchecked Sendable` with `NSLock` for its connection registry. | `Sources/TursoKit/TursoDatabase.swift:8` | Convert `TursoDatabase` to an actor; serialize `connect`, `close`, and the weak connection registry on that actor. |
| 1.3 | Medium | `LiveQuery` / `LiveQueryOne` store `Task` references in `nonisolated(unsafe)`. | `Sources/BoutiqueDB/LiveQuery.swift:21-22`, `Sources/BoutiqueDB/LiveQueryOne.swift:26-27` | Swift does not allow `nonisolated` on mutable `var` properties; `nonisolated(unsafe)` is the standard spelling for mutable `Sendable` task handles. Keep it with a safety comment. |
| 1.4 | High | `BoutiqueDBConnection` is not `Sendable` but used in `@Sendable` closures. | `Sources/BoutiqueDB/BoutiqueDBConnection.swift:8` | Mark `Sendable` (it is a value type wrapping a locked connection) or pass a `Sendable` handle into closures. |
| 1.5 | High | `TursoConnection.execute` / `query` are synchronous blocking public APIs. | `Sources/TursoKit/TursoConnection.swift:84,98` | Convert to `async` actor methods; keep synchronous package/internal shims only where `DatabaseActor` already holds isolation. |
| 1.6 | High | `DatabaseActor.withExclusive` spin-waits on `exclusiveDepth`. | `Sources/BoutiqueDB/DatabaseActor.swift:209-210` | Replace with an `AsyncSemaphore`/continuation queue or actor re-entrancy guard that does not burn CPU. |
| 1.7 | Medium | `BoutiqueDB.init` is synchronous `throws` even though `BoutiqueDB.open` is async. | `Sources/BoutiqueDB/BoutiqueDB.swift:56`, `Sources/BoutiqueDB/BoutiqueDB+Open.swift:6` | Deprecate/document `init` as internal/advanced and steer users to `await BoutiqueDB.open(...)`. |
| 1.8 | Medium | `TursoCKSyncEngine.start` is synchronous `throws`. | `Sources/TursoCKSync/TursoCKSyncEngine.swift:89` | Make `start()` async and run `CKSyncEngine` setup off the main actor. |
| 1.9 | Medium | `TursoStore` uses `nonisolated(unsafe)` for listener task and continuations. | `Sources/TursoObservation/TursoInvalidation.swift:32-33` | For `Task` storage, `nonisolated(unsafe)` is required for mutable `var` properties; keep it. For `continuations`, protect the dictionary with a lock or move to a dedicated `actor ContinuationStore` to avoid unsynchronized mutation. |

### 2. Observation & CloudKit sync lifecycle

| # | Severity | Finding | File:line | Action |
|---|----------|---------|-----------|--------|
| 2.1 | High | `TursoStore` polls CDC every 250 ms; `sdk-kit` provides no `update_hook`/push callback. | `Sources/TursoObservation/TursoInvalidation.swift:81-106`, `Sources/CTursoSDK/include/turso.h` | Reduce poll interval for local writes (instant invalidation already exists), bound cross-process poll, and add an `AsyncStream` surface so `LiveQuery` can subscribe without polling when a future sdk-kit hook arrives. |
| 2.2 | High | Account change detection is not registered with `NotificationCenter` for runtime iCloud account switches. | `Sources/TursoCKSync/TursoCKSyncEngine.swift:163-172` | Listen to `NSUbiquityIdentityDidChangeNotification` and route through `noteAccountIdentity`/`applyAccountStatus`. |
| 2.3 | High | `docs/sync-overview.md` requires Push Notifications + `remote-notification` background mode, but no `BGTaskScheduler`/push integration exists. | `docs/sync-overview.md:19` | Implement `BGTaskScheduler` / `BGAppRefreshTask` / remote-notification handling and register it with `BoutiqueDBSyncEngine` lifecycle. |
| 2.4 | Medium | `BoutiqueDBSyncEngine` auto-drain runs synchronously on `@MainActor` after every write. | `Sources/BoutiqueDB/BoutiqueDBSyncEngine.swift:70-73` | Drain CDC asynchronously on `DatabaseActor`/sync actor and surface errors through `SyncStatus`. |
| 2.5 | Medium | `unsafeConnection` bypasses `DatabaseActor` serialization. | `Sources/BoutiqueDB/BoutiqueDB.swift:130` | Replace sync-engine init with an actor-safe attachment API (e.g. `db.attachSyncEngine(_:)`) that does not leak the raw connection. |
| 2.6 | Medium | `CloudKitSyncAdapter` uses `@unchecked Sendable` with `NSLock`. | `Sources/TursoCKSync/SyncAdapter.swift:83` | Convert to an actor or to `Sendable` continuations with proper isolation. |
| 2.7 | Medium | Echo suppression scans up to 10,000 CDC rows per inbound apply. | `Sources/TursoCKSync/TursoCKSyncEngine.swift:503` | Bound the scan to the actual changed row or use a `turso_cdc` row-tag / `change_time` window. |
| 2.8 | Medium | `lastWriterWins` conflict resolution silently falls back to the server on bad record identity. | `Sources/TursoCKSync/TursoCKSyncEngine.swift:525-560` | Surface the conflict parse failure to `SyncStatus` instead of silently overwriting local data. |
| 2.9 | Low | `LiveQuery` has no restart logic if `TursoStore.subscribe()` stream ends. | `Sources/BoutiqueDB/LiveQuery.swift:92-99` | Add stream-termination detection and re-subscription. |
| 2.10 | Low | LiveQuery integration tests do not assert instant local invalidation. | `Tests/BoutiqueDBTests/LiveQueryIntegrationTests.swift:46-80` | Add deterministic CDC timing tests (e.g. `advanceFromCDC` + `#expect`). |

### 3. Turso feature surface, docs, and DSL

| # | Severity | Finding | File:line | Action |
|---|----------|---------|-----------|--------|
| 3.1 | Critical | Docs show `USING tantivy`, but the macro emits `USING fts`. | `docs/turso-features-in-apple-apps.md:34`, `docs/guides/fts-and-vector.md:25`, `Sources/BoutiqueDBMacros/FTSIndexMacro.swift:84` | Align all docs and macro output to the actual Turso SQL (`USING fts(...)`); add a macro snapshot test. |
| 3.2 | High | `@GeneratedColumn` attribute is referenced in the macro but the attribute/macro does not exist. | `Sources/BoutiqueDBMacros/BoutiqueTableMacro.swift:116` | Remove the dead `GeneratedColumn` reference until a macro with a validated API shape is designed and tested. |
| 3.3 | High | `BoutiqueDB-TursoFeatures.md` still claims `bindings/c` limitations. | `BoutiqueDB-TursoFeatures.md:15` | Rewrite the feature-caveat section to reflect the current `sdk-kit` `turso_database_config_t` capabilities. |
| 3.4 | High | `BoutiqueDB-Design.md` still describes the old `bindings/c` / `libturso_sqlite3` engine binding. | `BoutiqueDB-Design.md:24` | Update the design doc to the `sdk-kit` / `turso.h` reality. |
| 3.5 | Medium | MVCC enabling logic is conditional and undocumented. | `Sources/BoutiqueDB/BoutiqueDB.swift:98-100` | Document that `concurrentWrites` enables MVCC only when `enableCDC == false`; otherwise it uses busy-retry. |
| 3.6 | Medium | Main Turso features have incomplete Swift API/DSL surfaces. | `Sources/TursoKit/TursoOpenOptions.swift:12`, `Sources/StructuredQueriesTurso/Vector32.swift:51`, `Sources/BoutiqueDB/Schema/TursoCapabilities.swift:9-17`, `Sources/StructuredQueriesTurso/TursoFunctions.swift:100-103` | Complete main surfaces: `Vector32Sparse` distance helpers, `customTypes`/`STRICT` column support + capability probe. Defer `attach` and `regexp_like` as niche. |
| 3.7 | Low | Doc/examples are stale or incomplete. | `docs/turso-features-in-apple-apps.md:124-125`, `docs/getting-started/installation.md:29`, `Package.swift:22-27`, `docs/contributors/sync-benchmarks.md` | Fix the encryption example (`encryption:` enum, not `cipher:`), update the Swift tools version to `6.1`, document `BOUTIQUE_LOCAL_TURSO_SDK`, and fill or remove empty benchmark tables. |

### 4. Packaging, DX, and Apple-ecosystem readiness

| # | Severity | Finding | File:line | Action |
|---|----------|---------|-----------|--------|
| 4.1 | Critical | Binary target URL may not be publicly accessible. | `Package.swift:20` | Make the repo public and confirm the `v0.2.1` release asset is multi-arch; update `tursoSDKChecksum` if the zip changes. |
| 4.2 | High | SPI OAuth and GitHub Actions billing are still unchecked. | `docs/contributors/publishing.md:25-26` | Complete SPI "Add a Package" OAuth and unlock GitHub Actions billing (`.spi.yml` already has `macos-xcodebuild` and `ios` platforms). |
| 4.3 | Medium | Consumer example is macOS-only and minimal. | `Examples/Consumer/Package.swift:6`, `Examples/Consumer/Sources/BoutiqueDBConsumer/main.swift` | Add an iOS target and a minimal SwiftUI demo covering `@Table`, `@LiveQuery`, and at least one Turso feature (FTS or vector). |
| 4.4 | Medium | iOS CI uses a generic simulator destination. | `.github/workflows/swift.yml:116` | Pin to `platform=iOS Simulator,name=iPhone 16` to match the SPI checklist. |
| 4.5 | Medium | Release docs reference a `public` remote that is not documented. | `docs/contributors/publishing.md:58` | Fix instructions to use `origin` or document the `public` remote setup. |

## Decisions

1. **Swift 6 strategy for low-level handles**: Convert `TursoConnection` and `TursoDatabase` to actors. Public low-level API moves to `async`; keep synchronous shims only inside `DatabaseActor`/internal call sites where isolation is already held.
2. **Repo visibility**: Make the repo public before SPI; verify the `v0.2.1` release asset and `Package.swift` checksum.
3. **CloudKit background sync**: Background sync (`BGTaskScheduler`, remote-notification handling) is required for v0.2.
4. **Feature completeness**: Ship the main features (FTS/vector DSL, MVCC, encryption, custom types/STRICT, CloudKit sync) before tagging; defer niche helpers (`attach`, `regexp_like`) to a later release.

## References

- `Sources/CTursoSDK/include/turso.h` — official sdk-kit C ABI.
- `BoutiqueDB-Design.md`, `BoutiqueDB-TursoFeatures.md` — design docs (partially stale).
- `docs/turso-features-in-apple-apps.md`, `docs/guides/fts-and-vector.md`, `docs/sync-overview.md`, `docs/guides/cloudkit-sync.md`, `docs/guides/live-queries.md` — user-facing docs.
- `docs/contributors/spi-checklist.md`, `docs/contributors/multi-arch-packaging.md`, `docs/contributors/publishing.md` — SPI/App Store readiness.
- Turso sdk-kit C API: <https://github.com/tursodatabase/turso/blob/809b4410/sdk-kit/turso.h>
- Turso experimental features: <https://docs.turso.tech/sql-reference/experimental-features>
- SQLiteData patterns: <https://github.com/pointfreeco/sqlite-data>, <https://www.pointfree.co/blog/posts/168-sharinggrdb-a-swiftdata-alternative>
- GRDB concurrency / `ValueObservation`: <https://groue-grdb-swift.mintlify.app/advanced/concurrency>, <https://groue.github.io/GRDB.swift/docs/5.25/Structs/ValueObservation.html>
