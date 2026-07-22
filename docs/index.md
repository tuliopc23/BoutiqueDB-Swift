# BoutiqueDB

BoutiqueDB is a local-first Swift persistence layer built on the [Turso](https://github.com/tursodatabase/turso) database engine. It combines SQLiteData-style ergonomics with a modern Swift concurrency model, change-data-capture (CDC) live queries, CloudKit synchronization, and opt-in access to Turso-only features such as full-text search, vector search, materialized views, and concurrent writes.

```swift
import BoutiqueDB
import StructuredQueries

let db = try await BoutiqueDB.open(
  url: BoutiqueDB.applicationSupportURL(),
  migrations: AppMigrations.plan
)

try await db.write { conn in
  try conn.execute(
    "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
    [.text("1"), .text("Hello"), .text("")]
  )
}

let rows = try await db.fetchAll(Note.self)
```

## What BoutiqueDB is

BoutiqueDB is designed for Apple apps that need:

- **Reliable local persistence** with a SQLite-compatible file format.
- **Modern Swift concurrency** (`async`/`await`, `Actor`, `Sendable`).
- **Reactive UI updates** through `LiveQuery` and `LiveQueryOne`.
- **CloudKit sync** via `CKSyncEngine` without maintaining a separate sync backend.
- **Optional Turso engine features** such as FTS, vector indexes, materialized views, and `BEGIN CONCURRENT`.

It is not a hosted database service. Your data lives in the app’s sandbox and can sync through CloudKit or a future adapter.

## Why Turso

BoutiqueDB uses a vendored, multi-arch `TursoSDK.xcframework` built from the official `sdk-kit` C ABI (`turso.h`). This gives the framework:

- A SQLite-compatible file format and dialect.
- A cooperatively async I/O core exposed through `DatabaseActor`.
- Official experimental feature flags (`views`, `index_method`, `generated_columns`, `encryption`, `multiprocess_wal`, and others).
- A path toward incremental view maintenance, vector search, and multi-process WAL sharing.

> **Note:** The engine is a Turso fork (`BoutiqueDB`) maintained for the Swift package. It is not a general-purpose Turso build; multi-language bindings and non-Apple packaging are out of scope.

## Where to start

- [Installation](getting-started/installation)
- [Quick start](getting-started/quick-start)
- [How the stack fits together](stack)
- [Why BoutiqueDB instead of SQLite directly](why-boutiquedb)
