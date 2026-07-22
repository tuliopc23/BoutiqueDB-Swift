# BoutiqueDB — Swift Persistence Framework Design

#boutiquedb #turso #swift #persistence #cloudkit #design

## 1. What this project is

`BoutiqueDB` (renamed from `TursoCloudKit`) is a **local-first Swift persistence framework** built on the Rust Turso engine with Apple CloudKit sync. It lives at `~/Developer/BoutiqueDB` and is the Swift package to evolve into a higher-level, SQLiteData-style framework.

## 2. Current architecture

```
BoutiqueDB/
├── Package.swift                         # name: BoutiqueDB
├── Sources/
│   ├── CTursoSQLite3/                    # C target wrapping bindings/c sqlite3.h
│   ├── TursoKit/                         # low-level handle: Database, Connection, Statement, Value, CDC
│   ├── StructuredQueriesTurso/           # Swift-StructuredQueries driver for @Table models
│   ├── TursoCKSync/                      # CKSyncEngine bridge + CDC sync
│   └── TursoObservation/                 # TursoStore / TursoQueryBox polling invalidation
└── Vendor/
    └── TursoSQLite3.xcframework          # prebuilt libturso_sqlite3 (macOS arm64)
```

- **Engine binding**: uses the `bindings/c` SQLite3 compatibility layer (`libturso_sqlite3.a`), not the newer `sdk-kit` C API.
- **Query DSL**: Point-Free's `swift-structured-queries` with `@Table`, `@Column`, `#sql`, etc.
- **Observation**: manual `TursoStore` polling of `turso_cdc`; no `@LiveQuery` property wrapper yet.
- **Sync**: `TursoCKSyncEngine` using `CKSyncEngine`, `SyncMetadataStore`, `RecordMapper`.

## 3. Binding decision

The project already links `libturso_sqlite3` from `bindings/c`. This is the fastest path because:

- It gives a normal SQLite3 API surface that `swift-structured-queries` can consume.
- It avoids writing a new driver for the `sdk-kit` native API.
- The main missing SQLite hooks (`update_hook`, `commit_hook`, etc.) are worked around via **Turso CDC** (`PRAGMA capture_data_changes_conn`).

Future option: migrate to `sdk-kit/turso.h` if we need Turso's cooperative async I/O, MVCC `BEGIN CONCURRENT`, or encryption. For a SQLiteData-like higher-level framework, the SQLite3 layer is sufficient today.

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

- Keep building `libturso_sqlite3` with `Scripts/build-turso.sh` (depends on `../turso-src`).
- The Swift package uses `unsafeFlags` to link the prebuilt static lib; this is acceptable for local/team but blocks Swift Package Index. For SPI, move to an `xcframework` binary target and a release pipeline.

## 10. Current status

- [x] `BoutiqueDB` Swift package product and target added.
- [x] `BoutiqueDB` container with `read`/`write`, `execute`, `fetchAll`, `fetchOne`.
- [x] `BoutiqueDBConnection` wrapper for transactions.
- [x] `LiveQuery` and `LiveQueryOne` property wrappers that observe CDC and refresh.
- [x] `BoutiqueDBSyncEngine` wrapper over `TursoCKSyncEngine`.
- [x] `BoutiqueDBTests` with CRUD and `@LiveQuery` refresh assertions.
- [x] `swift build` and `swift test` pass.
- [x] `Scripts/build-turso.sh` updated to avoid copying the `.dylib` whose install name breaks `swift test`.

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

- Stay on `bindings/c` SQLite3 compat for v2; `sdk-kit` migration is post-v2 (BD-013).
- Minimum OS remains iOS 17 / macOS 14 for `CKSyncEngine`; `swift-perception` back-ports observation to iOS 15 / macOS 12 (BD-006).
- Module names stay: `TursoKit`, `StructuredQueriesTurso`, `TursoObservation`, `TursoCKSync`, `BoutiqueDB` (umbrella), plus the new `BoutiqueDBMacros` target.
