# Concurrency

BoutiqueDB is designed around Swift concurrency and actor isolation. Getting the rules right avoids deadlocks and data races.

## Actor layout

| Type | Actor | Use |
|------|-------|-----|
| `BoutiqueDB` | `@MainActor` | Container, SwiftUI model host, `LiveQuery` owner |
| `DatabaseActor` | background | All engine reads and writes |
| `TursoStore` | background + `MainActor` bridge | Change event stream |

## Read and write

```swift
try await db.write { conn in
  try conn.execute("INSERT INTO notes (title) VALUES (?)", [.text("Hello")])
}

let notes = try await db.read { conn in
  try Note.all.fetchAll(conn)
}
```

Closures run on `DatabaseActor`. Do not call `@MainActor` `BoutiqueDB` methods from inside the closure.

## Concurrent writes with MVCC

```swift
let db = try BoutiqueDB(
  url: url,
  concurrentWrites: true,
  migrations: AppMigrations.plan
)

try await db.writeConcurrent { conn in
  try conn.execute("INSERT INTO ...")
  // commits with optimistic conflict detection
}
```

`writeConcurrent` uses `BEGIN CONCURRENT` and retries on `SQLITE_BUSY` conflicts with exponential backoff.

## Rules

1. **Never call `BoutiqueDB` from inside a `DatabaseActor` body.** `BoutiqueDB` is `@MainActor`; doing so can deadlock.
2. **Use `read` for read-only work.** It takes a read-only connection.
3. **Use `write` for single-writer transactions.** It uses deferred/immediate transactions.
4. **Use `writeConcurrent` only when contention is real.** MVCC adds retry complexity and is mutually exclusive with CDC on the same connection.
5. **Finish statements before starting another write on the same connection.** Same-connection write statements return `SQLITE_BUSY` in Turso to keep the connection state safe.

## Async I/O

Enable `asyncIO` in `TursoOpenOptions` to make `step()` yield at I/O boundaries:

```swift
let db = try BoutiqueDB(url: url, openOptions: .tursoEnhancedAsync)
```

This is recommended for apps that perform large imports or long-running writes.
