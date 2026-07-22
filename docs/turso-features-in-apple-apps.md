# Turso features in Apple apps

The Turso engine adds several features that stock SQLite does not have. This guide explains how to use them in iOS and macOS apps, how to probe for them, and what to watch out for.

## Enabling Turso features

All experimental features are opt-in through `TursoOpenOptions`:

```swift
let db = try BoutiqueDB(
  url: url,
  openOptions: .tursoEnhanced  // views + index_method + generated_columns + vacuum + without_rowid
)
```

The complete list of tokens:

`views` · `custom_types` · `encryption` · `index_method` · `autovacuum` · `vacuum` · `attach` · `generated_columns` · `without_rowid` · `multiprocess_wal` · `mvcc_passive_checkpoint`

BoutiqueDB maps these to `TursoExperimentalFeature` and builds a comma-separated string for `turso_database_config_t`.

## Capability probes

After opening, `db.capabilities` tells you which features the build actually supports:

```swift
guard db.capabilities.ftsIndex else {
  // fall back to LIKE search
  return
}
guard db.capabilities.vectorIndex else {
  // brute-force cosine comparison in Swift
  return
}
```

Always gate user-facing Turso features on a capability probe so your app degrades gracefully if the vendored `TursoSDK` is built without the right flags.

## Full-text search (Tantivy)

Turso uses the [Tantivy](https://github.com/quickwit-oss/tantivy) search library for full-text search.

### Declare an index

```swift
@BoutiqueTable
@FTSIndex("title", "body", tokenizer: .default)
struct Article: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
  var updatedAt: Date
}
```

This emits:

```sql
CREATE INDEX article_title_body_fts ON articles USING fts(title, body) WITH (tokenizer = 'default')
```

### Query with FTS

```swift
let results = try await db.read { conn in
  try Article.where { $0.title.match("swift") }
    .order { $0.title.score("swift").desc() }
    .limit(20)
    .fetchAll(conn.connection)
}
```

Available helpers on `String` columns:

- `.match(_:)` — Tantivy boolean query.
- `.score(_:)` — BM25 relevance.
- `.highlight(query:before:after:)` — highlighted snippets.

Tokenizers: `default`, `raw`, `simple`, `whitespace`, `ngram`.

### Best practices

- Use `match` in the `WHERE` clause and `score` in `ORDER BY`.
- Store searchable text in dedicated columns; do not index JSON blobs.
- If the vendored build does not support `index_method`, fall back to `LIKE` or disable search.

## Vector search

Turso supports dense and sparse vector storage, distance functions, and optional `USING vector` indexes.

### Store embeddings

```swift
@BoutiqueTable
@VectorIndex("embedding", metric: .cosine)
struct Document: Sendable {
  @Column(primaryKey: true) let id: UUID
  var embedding: Vector32
}
```

`Vector32` is a `[Float]` wrapper that binds as a JSON-like literal.

### Similarity search

```swift
let query = Vector32([0.1, 0.2, 0.3])

let neighbors = try await db.read { conn in
  try Document.where { vectorDistanceCos($0.embedding, query) < 0.2 }
    .order { vectorDistanceCos($0.embedding, query) }
    .limit(10)
    .fetchAll(conn.connection)
}
```

Available distances: `vectorDistanceCos`, `vectorDistanceL2`, `vectorDistanceDot`, `vectorDistanceJaccard`.

### Sparse vectors

```swift
let sparse = Vector32Sparse([0: 1.0, 5: 0.5])
try await db.execute(
  "INSERT INTO docs (id, embedding) VALUES (?, vector32_sparse(?))",
  [.text(id.uuidString), .text(sparse.jsonLiteral)]
)
```

### Best practices

- Dimensionality must match the index. Use fixed-size embeddings from one model.
- Normalize embeddings for cosine distance if your model does not already do so.
- Build the vector index only when the table is large enough; small tables do not benefit.

## Materialized views (incremental view maintenance)

Materialized views auto-update when base tables change.

### Define a view

```swift
@MaterializedView(name: "tag_counts", as: """
  SELECT tag, COUNT(*) AS count FROM notes GROUP BY tag
""")
struct TagCount: Sendable, Table {
  var tag: String
  var count: Int64
}
```

Then create it:

```swift
try await db.create(TagCount.self)
```

Query it like a table:

```swift
let counts = try await db.read { conn in
  try TagCount.all.fetchAll(conn.connection)
}
```

### Limitations

- No nested materialized views.
- `WITHOUT ROWID` and `TEMPORARY` are not allowed in source SQL.
- Complex aggregations may be rejected.
- Always gate on `db.capabilities.materializedViews`.

## Generated columns

```swift
@BoutiqueTable
struct Note: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  @GeneratedColumn("lower(title)") var lowercasedTitle: String
}
```

This creates:

```sql
CREATE TABLE notes (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  lowercasedTitle TEXT GENERATED ALWAYS AS (lower(title)) VIRTUAL
)
```

Virtual generated columns are recomputed on read and do not take extra storage. Use them for case-insensitive search or derived values.

## `STRICT` and `WITHOUT ROWID`

```swift
@BoutiqueTable(strict: true, withoutRowid: true)
struct Setting: Sendable {
  @Column(primaryKey: true) var key: String
  var value: String
}
```

- `STRICT` enforces declared types and rejects unknown types.
- `WITHOUT ROWID` stores rows keyed by the primary key, reducing indirection for key-value tables.

> **Warning:** `STRICT` does not support every SQLite type; use `TEXT`, `INTEGER`, `REAL`, `BLOB`, `ANY`.

## Cooperative async I/O

Enable `asyncIO` so the engine yields at I/O boundaries:

```swift
let db = try BoutiqueDB(
  url: url,
  openOptions: .tursoEnhancedAsync
)
```

This maps to the official `sdk-kit` `async_io` flag. The `DatabaseActor` drives `TURSO_IO` with `Task.yield()` so other Swift tasks can run during long writes.

Use async I/O when:

- Importing large datasets on the main actor's behalf.
- Running with encryption or multi-process WAL.
- You observe UI hitches during writes.

## MVCC and `BEGIN CONCURRENT`

Turso supports multi-version concurrency control for optimistic concurrent writers.

```swift
let db = try BoutiqueDB(
  url: url,
  enableCDC: false,
  concurrentWrites: true
)

try await db.beginConcurrent()
try await db.writeConcurrent { conn in
  try Note.insert { ... }.execute(conn.connection)
}
try await db.commitConcurrent()
```

> **Important:** CDC and MVCC are mutually exclusive on the same connection handle. With CDC enabled, `writeConcurrent` uses busy-retry `BEGIN IMMEDIATE` instead.

## Encryption

BoutiqueDB supports Turso's at-rest encryption. Provide a 32-byte key stored in the Keychain:

```swift
let key = try loadKeyFromKeychain()  // 32 bytes for aegis256
let db = try BoutiqueDB(
  url: url,
  encryption: .aegis256(key: key)
)
```

Ciphers: `aegis256` (32 bytes), `aes256gcm` (32 bytes).

> **Warning:** If the key is lost, the database cannot be decrypted. Back up keys separately and never commit them.

## Multi-process WAL

Share a database between your app and an extension:

```swift
let url = FileManager.default
  .containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.app")!
  .appendingPathComponent("shared.db")

let db = try BoutiqueDB(
  url: url,
  multiProcess: true
)
```

Requirements:

- Enable App Group entitlement.
- Use a file inside the shared container.
- Multi-process WAL requires the `multiprocess_wal` token and a compatible engine build.

## Custom types and `CREATE TYPE`

The `custom_types` token enables `CREATE TYPE` and `CREATE DOMAIN` for `STRICT` tables. These are advanced features; map them to `RawRepresentable` Swift enums with a `QueryBindable` conformance.

## Scalar extensions

Turso bundles extensions such as UUID, regexp, and percentile. BoutiqueDB exposes some through the DSL:

```swift
let id = try await db.read { conn in
  try conn.queryOne("SELECT uuid4_str() AS id")?["id"]?.stringValue
}

let p95 = try await db.read { conn in
  try conn.queryOne("SELECT percentile(value, 0.95) AS p FROM metrics")?["p"]?.doubleValue
}
```

Use `TursoSQL.uuid4()` and `TursoSQL.percentile(_:_:)` from `StructuredQueriesTurso` for typed query fragments.

## Summary checklist

| Feature | Token | Capability | Best practice |
|---------|-------|------------|---------------|
| FTS | `index_method` | `capabilities.ftsIndex` | Use Tantivy `match`/`score` |
| Vector search | `index_method` (index), no token for functions | `capabilities.vectorIndex` / `vectorFunctions` | Normalize, probe first |
| Materialized views | `views` | `capabilities.materializedViews` | Avoid nested views |
| Generated columns | `generated_columns` | `capabilities.generatedColumns` | Virtual columns for derived values |
| `STRICT` / `WITHOUT ROWID` | `without_rowid` / `generated_columns` | n/a | Use `@BoutiqueTable` |
| Async I/O | `async_io` (boolean) | `connection.usesAsyncIO` | Enable for large writes |
| MVCC | `mvcc_passive_checkpoint` | `capabilities.mvcc` | Not with CDC |
| Encryption | `encryption` | `capabilities.encryption` | Keychain-only keys |
| Multi-process WAL | `multiprocess_wal` | `capabilities.multiProcessWAL` | App Group container |
