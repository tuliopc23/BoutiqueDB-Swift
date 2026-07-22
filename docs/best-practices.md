# Best practices

This guide collects recommendations for building maintainable, performant BoutiqueDB apps.

## Model design

### Prefer structs with value semantics

```swift
@Table
struct Note: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
  var updatedAt: Date
}
```

Value-typed models are easy to pass across actors and SwiftUI views. They are not uniqued or auto-updating like Core Data objects; re-fetch when the database changes.

### Use stable primary keys

UUID strings and integers work well. Avoid `AUTOINCREMENT` for tables that participate in CloudKit sync (`TursoCKSyncError.autoIncrementPrimaryKeyUnsupported`).

### Store timestamps for conflict resolution

```swift
@Table
struct Note: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var updatedAt: Date
}
```

Use `updatedAt` with `ConflictPolicy.lastWriterWins(field: "updatedAt")`.

### Keep models focused

A model should map to one table. For relationships, store foreign keys and query across tables, or use denormalized columns for read-heavy paths. BoutiqueDB does not manage object graphs for you.

## Migrations

### Append-only, never edit shipped migrations

```swift
enum AppMigrations {
  static let plan = BoutiqueMigrationPlan {
    BoutiqueMigration("v1_create_notes") { conn in
      for sql in Note.boutiqueCreateStatements { try conn.execute(sql) }
    }
    BoutiqueMigration("v2_add_notes_tag") { conn in
      try conn.execute("ALTER TABLE notes ADD COLUMN tag TEXT")
    }
  }
}
```

### Make migrations idempotent

Use `IF NOT EXISTS` in DDL. For data backfills, use `UPDATE OR IGNORE` or a `CASE` expression.

### Use `eraseDatabaseOnSchemaChange` only in DEBUG

```swift
BoutiqueMigrationPlan(eraseDatabaseOnSchemaChange: true) { ... }
```

This is useful for rapid iteration, but never in production. It throws `BoutiqueError.schemaErasedForDebug` and `BoutiqueDB.open` re-creates the file.

## Concurrency

### Never call `BoutiqueDB` from inside a `DatabaseActor` closure

```swift
// WRONG — can deadlock
try await db.write { conn in
  let other = try await db.read { _ in ... }
}
```

### Run all engine work through `read`/`write`

Do not keep a long-lived `TursoConnection` outside those scopes. `unsafeConnection` is only for sync attachment and advanced use.

### Use `writeConcurrent` for contention

```swift
try await db.writeConcurrent { conn in
  try Note.insert { ... }.execute(conn.connection)
}
```

With CDC enabled this uses busy-retry `BEGIN IMMEDIATE`. With CDC disabled it uses `BEGIN CONCURRENT`. Both retry on `SQLITE_BUSY` up to 8 attempts with exponential backoff.

## Error handling

### Surface open failures

```swift
.task {
  do {
    let db = try await BoutiqueDB.open(...)
    ...
  } catch {
    openError = String(describing: error)
  }
}
```

### Check capabilities before using Turso features

```swift
guard db.capabilities.ftsIndex else {
  // degrade: plain LIKE search
  return
}
```

### Do not ignore `lastPostCommitError`

`onLocalCommit` and post-commit observers can fail after the transaction commits. Inspect `db.lastPostCommitError` in diagnostics or debug builds.

## Testing

- Use a unique temporary database per test.
- Build a test helper that opens with `.tursoEnhanced` and applies migrations.
- Use `BOUTIQUE_LOCAL_TURSO_SDK=1 swift test` when testing a local engine build.
- For CloudKit sync, test on a physical device with a production container.

## Security

- Store encryption keys in the Keychain, never hard-code them.
- Use Data Protection (`NSFileProtectionComplete`) for sensitive databases.
- Do not commit `Vendor/TursoSDK.xcframework` or `.a` files to git.

## Dependency injection

With `swift-dependencies`:

```swift
extension DependencyValues {
  var boutiqueDB: BoutiqueDB {
    get { self[BoutiqueDBKey.self] }
    set { self[BoutiqueDBKey.self] = newValue }
  }
}

private enum BoutiqueDBKey: DependencyKey {
  static let liveValue: BoutiqueDB? = nil
}
```

Open the database first, then `prepareDependencies { $0.boutiqueDB = db }`.
