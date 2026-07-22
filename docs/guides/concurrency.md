# Concurrency

BoutiqueDB is designed around Swift concurrency and actor isolation. Getting the rules right avoids deadlocks and data races.

## Actor layout

| Type | Actor | Use |
|------|-------|-----|
| `BoutiqueDB` | `@MainActor` | Container, SwiftUI model host, `LiveQuery` owner |
| `DatabaseActor` | isolated | All engine reads and writes |
| `TursoStore` | `MainActor` bridge | Change event stream |

## Read and write

```swift
try await db.write { conn in
  try conn.execute("INSERT INTO notes (title) VALUES (?)", [.text("Hello")])
}

let notes = try await db.read { conn in
  try Note.all.fetchAll(conn.connection)
}
```

Closures run on `DatabaseActor`. Do not call `@MainActor` `BoutiqueDB` methods from inside the closure.

## Concurrent writes

```swift
let db = try BoutiqueDB(
  url: url,
  concurrentWrites: true
)

try await db.writeConcurrent { conn in
  try conn.execute("INSERT INTO ...", [...])
}
```

With CDC enabled, `writeConcurrent` uses busy-retry `BEGIN IMMEDIATE` on the primary handle so CDC is always captured.

With CDC disabled, it enables MVCC (`PRAGMA journal_mode = mvcc`) and uses `BEGIN CONCURRENT`.

## Manual MVCC transactions

When CDC is disabled, you can use explicit concurrent transactions:

```swift
try await db.beginConcurrent()
try await db.writeConcurrent { conn in
  try conn.execute("INSERT INTO ...", [...])
}
try await db.commitConcurrent()
```

## Rules

1. **Never call `BoutiqueDB` from inside a `DatabaseActor` body.** `BoutiqueDB` is `@MainActor`; doing so can deadlock.
2. **Use `read` for read-only work.** It opens a read transaction.
3. **Use `write` for single-writer transactions.** It uses `BEGIN IMMEDIATE`.
4. **Use `writeConcurrent` when contention is real.** It retries `SQLITE_BUSY` with exponential backoff (max 8 attempts).
5. **Do not hold a `TursoConnection` outside `read`/`write`.** Use `unsafeConnection` only for sync attachment and diagnostics.
6. **Do not enable CDC and MVCC together.** `BoutiqueError.cdcMutuallyExclusiveWithMVCC` is thrown.

## Async I/O

Enable `asyncIO` in `TursoOpenOptions` to make the engine yield at I/O boundaries:

```swift
let db = try BoutiqueDB(url: url, openOptions: .tursoEnhancedAsync)
```

This is recommended for apps that perform large imports, encryption, or multi-process WAL operations.
