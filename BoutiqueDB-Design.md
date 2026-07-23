# BoutiqueDB — Swift Persistence Framework Design

#boutiquedb #turso #swift #persistence #cloudkit #design

## 1. What this project is

`BoutiqueDB` (renamed from `TursoCloudKit`) is a **local-first Swift persistence framework** built on the Rust Turso engine with Apple CloudKit sync. It lives at `~/Developer/BoutiqueDB` and is the Swift package to evolve into a higher-level, SQLiteData-style framework.

## 2. Current architecture

```
BoutiqueDB/
├── Package.swift                         # name: BoutiqueDB
├── Sources/
│   ├── CTursoSDK/                        # C target wrapping the sdk-kit `turso.h`
│   ├── TursoKit/                         # low-level handle: Database, Connection, Statement, Value, CDC
│   ├── StructuredQueriesTurso/           # Swift-StructuredQueries driver for @Table models
│   ├── TursoCKSync/                      # CKSyncEngine bridge + CDC sync
│   ├── TursoObservation/                 # TursoStore / TursoQueryBox polling invalidation
│   └── BoutiqueDBMacros/                 # @BoutiqueTable, @GeneratedColumn, @FTSIndex, @VectorIndex, @MaterializedView
└── Vendor/
    └── TursoSDK.xcframework              # prebuilt sdk-kit binary (macOS + iOS, local or downloaded)
```

- **Engine binding**: uses the official `sdk-kit` C API (`turso.h` / `libturso_sdk_kit`), not the older `bindings/c` SQLite3 compatibility layer.
- **Query DSL**: Point-Free's `swift-structured-queries` with `@Table`/`@Column`, plus BoutiqueDB macros `@BoutiqueTable`, `@GeneratedColumn`, `@FTSIndex`, `@VectorIndex`, and `@MaterializedView`.
- **Observation**: `TursoStore` polls `turso_cdc`; `@LiveQuery` and `@LiveQueryOne` property wrappers refresh on changes.
- **Sync**: `TursoCKSyncEngine` using `CKSyncEngine`, `SyncMetadataStore`, `RecordMapper`; `BoutiqueDBSyncEngine` provides a SwiftUI-friendly façade.

## 3. Binding decision

The project links the official `sdk-kit` `libturso_sdk_kit` via a binary `TursoSDK.xcframework` and the `CTursoSDK` C target wrapping `turso.h`. This gives:

- Full access to Turso-only features (`async_io`, MVCC `BEGIN CONCURRENT`, encryption, views, custom index methods, generated columns, etc.) through `turso_database_config_t`.
- A normal SQL execution surface that `swift-structured-queries` can consume.
- CDC (`PRAGMA capture_data_changes_conn`) for observation and sync, since `sdk-kit` does not expose `update_hook` or `commit_hook`.

The older `bindings/c` SQLite3 compatibility layer has been retired.

## 4. Macro / model layer

`swift-structured-queries` already provides the macro model layer:

```swift
import StructuredQueries

@Table
struct Note {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
}

// generated DSL:
try Note.insert { Note(id: uuid, title: "Hi", body: "") }.execute(conn)
let all = try Note.order { $0.title }.fetchAll(conn)
```

So the **lower/mid-level** (GRDB-ish) already exists. The **higher-level SQLiteData-style** pieces are missing:

- `@MainActor` `BoutiqueDB` container / actor.
- `@LiveQuery` / `@LiveQueryOne` property wrappers that auto-refresh on CDC changes.
- `write { }` / `read { }` async transactions.
- A `SyncEngine` that is easier to configure than `TursoCKSyncEngine`.
- CloudKit sync bundled by default, with a pluggable sync adapter protocol.

## 5. Proposed higher-level API (SQLiteData-level)

```swift
@MainActor
final class BoutiqueDB: Sendable {
  init(url: URL, configuration: Configuration = .init()) throws
  func read<T>(_ operation: (BoutiqueDBConnection) throws -> T) async throws -> T
  func write<T>(_ operation: (inout BoutiqueDBConnection) throws -> T) async throws -> T
}

@Observable final class NotesModel {
  @ObservationIgnored @LiveQuery(model.db) { Note.order { $0.title }.asSelect() } var notes: [Note]
  @ObservationIgnored @LiveQueryOne(model.db) { Note.where { $0.id.eq(noteID) }.asSelect() } var note: Note?
}

final class BoutiqueDBSyncEngine: Sendable {
  init(containerIdentifier: String, tables: [SyncedTable]) throws
  func start() async throws
}
```

## 6. Observation strategy

Use the existing **CDC polling** (`TursoStore`) plus a `BoutiqueDBInvalidator` that:

- Tracks the latest `change_id` per table from `turso_cdc`.
- Exposes a `ChangeToken` / `AsyncStream`.
- `LiveQuery` property wrapper subscribes and re-runs its query when an affected table changes.

Long term, replace polling with direct `sqlite3_update_hook` / `sqlite3_commit_hook` if the C compat layer implements them.

## 7. Sync

`TursoCKSync` already implements CloudKit sync. The remaining work:

- Wrap `TursoCKSyncEngine` in a friendlier `BoutiqueDBSyncEngine`.
- Define a `SyncAdapter` protocol so Turso Cloud sync can plug in later.
- Keep CloudKit as the bundled default, like SQLiteData.

## 8. Experimental Turso features to expose later

See `BoutiqueDB-TursoFeatures.md` for a full analysis of which Turso-exclusive features make sense as macros vs runtime APIs.

- MVCC / `BEGIN CONCURRENT`: API-level `writeConcurrent()` / `beginConcurrent()`.
- Async writes: make `write` / `transaction` `async` and run on a background actor.
- Vector type + `vector_distance_*`: add `Vector32`/`Vector32Sparse` types and DSL helpers.
- Full-text search (`fts`): DSL helpers (`fts_match`, `fts_score`, `fts_highlight`) and possibly an `@FTSIndex` macro.
- Materialized views (IVM): `@MaterializedView` macro or `createMaterializedView()` API.
- Generated columns / `WITHOUT ROWID` / `STRICT`: extend `@Table`/`@Column` options or add a `@BoutiqueTable` wrapper macro.

## 9. Packaging

- Build the multi-arch `TursoSDK.xcframework` with `Scripts/build-turso-sdk-xcframework.sh` (depends on `BoutiqueDB` engine source via `TURSO_SRC`, default `../BoutiqueDB`).
- The Swift package uses a binary target (`TursoSDK`) with no `unsafeFlags`, so it is SPI-safe. Release assets are published on GitHub Releases and referenced by `Package.swift`.

## 10. Current status

- [x] `BoutiqueDB` Swift package product and target added.
- [x] `BoutiqueDB` container with `read`/`write`, `execute`, `fetchAll`, `fetchOne`.
- [x] `BoutiqueDBConnection` wrapper for transactions.
- [x] `LiveQuery` and `LiveQueryOne` property wrappers that observe CDC and refresh.
- [x] `BoutiqueDBSyncEngine` wrapper over `TursoCKSyncEngine`.
- [x] `BoutiqueDBTests` with CRUD and `@LiveQuery` refresh assertions.
- [x] `swift build` and `swift test` pass.
- [x] `Scripts/build-turso-sdk-xcframework.sh` builds a multi-arch xcframework and avoids the install-name issues of a copied `.dylib`.

## 11. Immediate next steps

Implementation is now tracked in the OpenSpec change in the engine repo:

- OpenSpec (archived): `../BoutiqueDB/openspec/changes/archive/2026-07-22-boutiquedb-v2/`
- Refinement backlog: `../BoutiqueDB/BoutiqueDB-Refinement-Tasks.md`
- Open issues / blockers: `../BoutiqueDB/BoutiqueDB-Issues.md`

Top priorities from that task list:

1. Add `Migration`/`Schema` helpers for creating tables from `@Table`/`@BoutiqueTable` models (task 5.1).
2. Rewrite `LiveQuery`/`LiveQueryOne` to use `AsyncStream` over CDC (tasks 1.3–1.5).
3. Add `SyncAdapter` protocol for CloudKit/Turso Cloud sync (tasks 4.1–4.2).
4. Implement `@BoutiqueTable`, `@FTSIndex`, `@VectorIndex`, and `@MaterializedView` macros (tasks 2.1–2.6).

## 12. Open questions / decisions

Open questions, blockers, and risks are now maintained centrally in `../BoutiqueDB/BoutiqueDB-Issues.md` (BD-001 through BD-012). The key decisions resolved for v2 are:

- Migrated to the `sdk-kit` (`turso.h`) engine binding (BD-013).
- Minimum OS remains iOS 17 / macOS 14 for `CKSyncEngine`; `swift-perception` back-ports observation to iOS 15 / macOS 12 (BD-006).
- Module names stay: `TursoKit`, `StructuredQueriesTurso`, `TursoObservation`, `TursoCKSync`, `BoutiqueDB` (umbrella), plus `BoutiqueDBMacros` and `CTursoSDK`.
