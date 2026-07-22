# Models and tables

BoutiqueDB models are Swift structs annotated with `swift-structured-queries` macros and a BoutiqueDB-specific macro layer.

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

- A table descriptor.
- `Codable` conformance helpers.
- Query DSL entry points: `Note.all`, `Note.filter`, `Note.insert`, etc.

Models must be `Sendable` because they cross actor boundaries.

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
| `Vector32` | custom vector type |

`Optional` values are stored as `NULL`.

## Create a table at migration time

```swift
try await db.create(Note.self)
```

This emits `CREATE TABLE IF NOT EXISTS` using the `@Table` descriptor.

## Raw SQL escape hatch

Use `#sql` from `swift-structured-queries` for fragments that the DSL cannot express:

```swift
import StructuredQueries

let rows = try await db.read { conn in
  try Note
    .where(#sql("lower(title) LIKE ?", [.text("%swift%")]))
    .fetchAll(conn)
}
```

## BoutiqueDB macro extensions

The `BoutiqueDBMacros` module adds peer macros for Turso-specific features:

- `@BoutiqueTable` extends `@Table` with `WITHOUT ROWID`, `STRICT`, and generated column options.
- `@FTSIndex` declares a full-text index on selected columns.
- `@VectorIndex` declares a vector index with a distance metric.
- `@MaterializedView` defines an incremental view.

See [FTS and vector search](fts-and-vector) for examples.
