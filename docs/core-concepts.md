# Core concepts

BoutiqueDB is organized around a small number of concepts. Understanding them makes every other guide easier.

## 1. The database file

A BoutiqueDB database is a regular SQLite-compatible file on disk. You choose its URL:

```swift
let url = try BoutiqueDB.applicationSupportURL(filename: "app.db")
let db = try await BoutiqueDB.open(url: url, migrations: AppMigrations.plan)
```

You can use `FileManager` locations for:

- `.applicationSupportDirectory` — default persistent data.
- `.documentDirectory` — user-visible files.
- A shared App Group container — when combined with `multiProcess: true`.
- A temporary file — for tests and SwiftUI previews.

## 2. Models (`@Table` and `@BoutiqueTable`)

Models are Swift structs. `StructuredQueries` provides `@Table` for type-safe columns. BoutiqueDB adds `@BoutiqueTable` for Turso-specific table options.

```swift
import StructuredQueries

@Table
struct Note: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
  var updatedAt: Date = Date()
}

@BoutiqueTable(strict: true)
struct Setting: Sendable {
  @Column(primaryKey: true) var key: String
  var value: String
}
```

`@Table` gives you `Note.all`, `Note.where { ... }`, `Note.insert`, `Note.update`, and automatic `Codable`-style decoding.

`@BoutiqueTable` adds:

- `STRICT` and `WITHOUT ROWID` options.
- Generated columns via `@GeneratedColumn("lower(title)")`.
- Stacked `@FTSIndex` and `@VectorIndex` attributes.

## 3. Migrations

Migrations are append-only and identified by stable strings. They are not auto-generated.

```swift
enum AppMigrations {
  static let plan = BoutiqueMigrationPlan {
    BoutiqueMigration("v1_create_notes") { conn in
      for sql in Note.boutiqueCreateStatements {
        try conn.execute(sql)
      }
    }

    BoutiqueMigration("v2_add_updated_at") { conn in
      try conn.execute("""
        ALTER TABLE notes ADD COLUMN updatedAt TEXT NOT NULL DEFAULT '1970-01-01T00:00:00Z'
      """)
    }
  }
}
```

Transactional migrations run inside one native transaction with the bookkeeping insert. Asynchronous migrations suspend and must be idempotent.

## 4. Reads and writes

All engine I/O goes through the `DatabaseActor`.

```swift
try await db.write { conn in
  try Note.insert { Note(id: UUID(), title: "Hello", body: "") }
    .execute(conn.connection)
}

let notes = try await db.read { conn in
  try Note.all.order { $0.updatedAt.desc() }.fetchAll(conn.connection)
}
```

- `BoutiqueDB` is `@MainActor` so it is safe to own from SwiftUI.
- The closure runs on a background actor.
- Do **not** call `@MainActor` `BoutiqueDB` methods from inside the closure.

## 5. Live queries

`LiveQuery` and `LiveQueryOne` subscribe to `TursoStore` change events and re-run the query automatically.

```swift
@MainActor
final class NotesModel: Observable {
  @LiveQuery(db) { Note.all.order { $0.updatedAt.desc() }.asSelect() }
  var notes: [Note] = []
}
```

Local writes call `store.invalidate()` immediately; the CDC listener catches changes from other connections. The default poll interval is 250 ms.

## 6. CloudKit sync

`TursoCKSync` maps CDC changes to CloudKit records through `CKSyncEngine`. Only private-database sync is supported in the current beta.

```swift
let syncEngine = BoutiqueDBSyncEngine(
  db: db,
  syncedTables: [try SyncedTable(schema: NoteSchema.self)]
)
try syncEngine.attach(to: db, automaticallyDrain: true)
```

## 7. Turso features

Experimental engine features are enabled at open time through `TursoOpenOptions`:

```swift
let db = try BoutiqueDB(
  url: url,
  openOptions: .tursoEnhanced
)
```

`.tursoEnhanced` enables `views`, `index_method`, `generated_columns`, `vacuum`, and `without_rowid`. Other features (`encryption`, `multiprocess_wal`, `async_io`) are toggled separately.

## 8. Errors

BoutiqueDB surfaces high-level errors:

- `BoutiqueError.encryptionUnavailable`
- `BoutiqueError.multiProcessWALUnavailable`
- `BoutiqueError.featureUnavailable(_:)`
- `BoutiqueError.migrationFailed(id:message:)`
- `BoutiqueError.transactionInProgress`

Most `TursoError` values are wrapped as `BoutiqueError.sql(code:message:)`.
