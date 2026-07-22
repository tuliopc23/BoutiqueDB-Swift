# Models and tables

BoutiqueDB models are Swift structs annotated with `StructuredQueries` macros and a BoutiqueDB-specific macro layer.

## Define a table

```swift
import BoutiqueDB
import StructuredQueries

@Table
struct Note: Identifiable, Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
  var updatedAt: Date = Date()
}
```

`@Table` generates:

- A `Table` protocol conformance.
- A `PrimaryKeyedTable` conformance when a `@Column(primaryKey:)` exists.
- Query DSL entry points: `Note.all`, `Note.where { ... }`, `Note.insert`, `Note.update`.
- `Codable`-driven decoding from the database row.

Models must be `Sendable` because they cross `DatabaseActor` and `MainActor` boundaries.

## Column types

BoutiqueDB maps Swift types to SQLite storage classes:

| Swift type | SQLite storage |
|------------|----------------|
| `Int`, `Int64` | `INTEGER` |
| `Double`, `Float` | `REAL` |
| `String` | `TEXT` |
| `Data` | `BLOB` |
| `Date` | `TEXT` (ISO 8601) |
| `UUID` | `TEXT` |
| `Bool` | `INTEGER` (0/1) |
| `Vector32` | `TEXT` (JSON-like vector literal) |

`Optional` values are stored as `NULL`.

## Insert, update, delete

```swift
try await db.write { conn in
  try Note.insert { Note(id: uuid, title: "Hello", body: "") }
    .execute(conn.connection)

  try Note.where { $0.id.eq(uuid) }
    .update { $0.title = "Updated" }
    .execute(conn.connection)

  try Note.where { $0.id.eq(uuid) }
    .delete()
    .execute(conn.connection)
}
```

## Query a table

```swift
let recent = try await db.read { conn in
  try Note.where { $0.title.contains("swift") }
    .order { $0.updatedAt.desc() }
    .limit(50)
    .fetchAll(conn.connection)
}
```

## Project columns

```swift
let titles = try await db.read { conn in
  try Note.select { ($0.title, $0.updatedAt) }
    .fetchAll(conn.connection)
}
```

## Raw SQL escape hatch

Use `#sql` from `StructuredQueries` for fragments the DSL cannot express:

```swift
let rows = try await db.read { conn in
  try Note
    .where(#sql("lower(title) LIKE ?", [.text("%swift%")]))
    .fetchAll(conn.connection)
}
```

## BoutiqueDB macro extensions

The `BoutiqueDBMacros` module adds peer macros for Turso-specific features:

- `@BoutiqueTable` extends `@Table` with `WITHOUT ROWID`, `STRICT`, and generated column options.
- `@FTSIndex` declares a full-text index on selected columns.
- `@VectorIndex` declares a vector index with a distance metric.
- `@MaterializedView` defines an incremental view.

```swift
@BoutiqueTable(strict: true)
@FTSIndex("title", "body")
@VectorIndex("embedding", metric: .cosine)
struct Article: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
  var embedding: Vector32
}
```

See [FTS and vector search](fts-and-vector) and [Turso features in Apple apps](../turso-features-in-apple-apps) for examples.
