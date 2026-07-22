# Performance tuning

BoutiqueDB is fast by default, but large datasets and complex queries need care. This guide covers the most impactful optimizations.

## Batch writes

Issuing one `write` per row is slow. Group rows in one transaction:

```swift
try await db.write { conn in
  for note in notes {
    try Note.insert { note }.execute(conn.connection)
  }
}
```

For very large imports, consider disabling `startListening` and calling `store.advanceFromCDC()` manually:

```swift
let db = try BoutiqueDB(url: url, startListening: false, migrations: AppMigrations.plan)
try await db.write { conn in
  for batch in notes.chunks(ofCount: 1000) {
    // insert batch
  }
}
db.store.startListening()
```

## Indexes

Add SQLite indexes for common filters and sorts:

```swift
try await db.execute(
  "CREATE INDEX IF NOT EXISTS notes_updated_at ON notes(updatedAt)"
)
```

For text search, use Turso's Tantivy FTS index:

```swift
@BoutiqueTable
@FTSIndex("title", "body")
struct Note: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
}
```

For vector search, use the `USING vector` index:

```swift
@BoutiqueTable
@VectorIndex("embedding", metric: .cosine)
struct Document: Sendable {
  @Column(primaryKey: true) let id: UUID
  var embedding: Vector32
}
```

## Query optimization

- Select only columns you need. `Note.all` decodes the full row; use `Note.select { ... }` for projections.
- Add `LIMIT` to `LiveQuery` results to keep refreshes fast.
- Order by indexed columns where possible.
- Avoid `LIKE '%term%'` without FTS.

## LiveQuery tuning

Each `LiveQuery` re-runs its query after every local commit. Reduce work:

- Limit result size.
- Use `@LiveQueryOne` for single-row screens.
- Share one `LiveQuery` across multiple views by sharing the model.
- For expensive queries, call `forceRefresh()` only when needed instead of observing every change.

The default CDC poll interval is 250 ms. You can customize it on `TursoStore` if you build it manually, but `BoutiqueDB` does not expose this directly.

## Concurrent writes

`writeConcurrent` can improve throughput when many writers contend:

```swift
let db = try BoutiqueDB(url: url, concurrentWrites: true)
```

With CDC enabled, this uses busy-retry immediate transactions. With CDC disabled, it uses `BEGIN CONCURRENT` (MVCC). MVCC may fail with `SQLITE_BUSY`; `writeConcurrent` retries automatically.

## Async I/O

Enable cooperative async I/O to keep long writes from blocking the `DatabaseActor`:

```swift
let db = try BoutiqueDB(url: url, openOptions: .tursoEnhancedAsync)
```

This is most helpful for large imports, encryption, or multi-process WAL workloads.

## Memory

- Do not cache large result sets in SwiftUI model objects; re-query on demand.
- Use `fetchOne` and `LIMIT` when only one row is needed.
- Close databases in tests and previews to release memory-mapped files.

## Profiling

Use Instruments:

- **Time Profiler** — see time in `DatabaseActor`.
- **File Activity** — observe WAL and database I/O.
- **Swift Concurrency** — detect blocked continuations.

Profile both macOS and iOS destinations before shipping.
