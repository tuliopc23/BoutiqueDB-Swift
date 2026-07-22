# BoutiqueDB

BoutiqueDB is a local-first Swift persistence framework built on the [Turso](https://github.com/tursodatabase/turso) database engine. It gives you SQLiteData-style ergonomics, CDC-backed live queries, CloudKit synchronization, and opt-in access to Turso-only features such as full-text search, vector search, materialized views, and concurrent writes.

```swift
import BoutiqueDB
import StructuredQueries

let db = try await BoutiqueDB.open(
  url: BoutiqueDB.applicationSupportURL(),
  migrations: AppMigrations.plan
)

try await db.write { conn in
  try Note.insert { Note(id: UUID(), title: "Hello", body: "") }
    .execute(conn.connection)
}

let rows = try await db.fetchAll(Note.self)
```

## What BoutiqueDB is

BoutiqueDB is designed for Apple apps that need:

- **Reliable local persistence** with a SQLite-compatible file format.
- **Modern Swift concurrency** (`async`/`await`, `Actor`, `Sendable`).
- **Reactive UI updates** through `LiveQuery` and `LiveQueryOne`.
- **CloudKit sync** via `CKSyncEngine` without maintaining a separate backend.
- **Optional Turso engine features** such as FTS, vector indexes, materialized views, and `BEGIN CONCURRENT`.

It is not a hosted database service. Your data lives in the app sandbox and can sync through CloudKit or a future adapter.

## Core principles

1. **Local-first.** The database file is authoritative. Sync is asynchronous and opportunistic.
2. **Swift-native.** Use `async`/`await`, `@Observable`, `@Table`, and property wrappers.
3. **Explicit is better than implicit.** Migrations are append-only and named. Schema sync is additive-only and opt-in.
4. **Turso features are opt-in.** Experimental engine flags are enabled through `TursoOpenOptions`, not forced on every open.
5. **Concurrency safety.** `BoutiqueDB` is `@MainActor`; all engine I/O runs on a `DatabaseActor`.

## Capability matrix

| Feature | Status | Notes |
|---------|--------|-------|
| Local CRUD with `@Table` / `StructuredQueries` | **Ready** | Type-safe model layer |
| `LiveQuery` / `LiveQueryOne` CDC observation | **Ready** | Cooperative polling, < 250 ms refresh |
| Concurrent writes | **Ready** | CDC-safe busy-retry or MVCC when CDC is off |
| CloudKit private-database sync | **Beta** | Test on physical device before shipping |
| Migrations | **Ready** | Append-only, transactional or asynchronous |
| Full-text search (Tantivy) | **Opt-in** | Requires `index_method` token |
| Vector search | **Opt-in** | Dense and sparse vectors, index method optional |
| Materialized views (IVM) | **Opt-in** | Requires `views` token |
| Generated columns, `STRICT`, `WITHOUT ROWID` | **Opt-in** | Via `@BoutiqueTable` |
| At-rest encryption | **Opt-in** | `aegis256` or `aes256gcm`, Keychain key |
| Multi-process WAL | **Opt-in** | App Group / extension sharing |

## Where to start

- [Core concepts](core-concepts)
- [Installation](getting-started/installation)
- [Quick start](getting-started/quick-start)
- [SwiftUI integration](swiftui-integration)
- [Turso features in Apple apps](turso-features-in-apple-apps)
