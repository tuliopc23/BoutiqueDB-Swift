# Migrations

BoutiqueDB follows the same production rules as **SQLiteData / GRDB**:

1. Migrations are **named, ordered, and append-only**.
2. Applied IDs live in `boutique_schema_migrations`.
3. **Never edit** a migration body after it has shipped.
4. Prefer typed helpers (`create`, `ensureColumn`) over ad-hoc SQL when possible.
5. Optional **additive-only** schema sync is for DEBUG / careful opt-in — not silent full auto-migrate.
6. The default synchronous closure is atomic with its tracking record. Use the explicitly labeled `asynchronous:` form only when suspension is unavoidable; asynchronous bodies must be idempotent because they cannot hold one native transaction across arbitrary suspension.

## Seamless open

```swift
let db = try await BoutiqueDB.open(
  url: try BoutiqueDB.applicationSupportURL(),
  concurrentWrites: true,
  migrations: AppMigrations.plan,
  schemaModels: [],           // optional BoutiqueSchema types
  schemaSync: .off            // or .additiveOnly in DEBUG
)
```

## Defining a plan

```swift
enum AppMigrations {
  static let plan = BoutiqueMigrationPlan(
    eraseDatabaseOnSchemaChange: false  // true only in DEBUG if you want GRDB-style erase
  ) {
    BoutiqueMigration("v1_create_notes") { connection in
      for statement in Note.boutiqueCreateStatements {
        try connection.execute(statement)
      }
    }
    BoutiqueMigration("v2_add_updated_at") { connection in
      try connection.execute(
        "ALTER TABLE notes ADD COLUMN updatedAt TEXT NOT NULL DEFAULT '1970-01-01T00:00:00Z'"
      )
    }
    BoutiqueMigration("v3_seed_defaults") { connection in
      try connection.execute(
        "INSERT OR IGNORE INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text("default"), .text("Welcome"), .text("Getting started"), .text(TursoDateFormatting.string(from: Date()))]
      )
    }
  }
}
```

## Additive columns

```swift
try await db.ensureColumn(
  table: "notes",
  name: "tag",
  sqlType: "TEXT",
  default: "''"
)
```

`ensureColumn` runs `ALTER TABLE ADD COLUMN IF NOT EXISTS`. It is idempotent and safe in migrations.

## Asynchronous migrations

Use only when you must `await` something (network, CloudKit, user consent):

```swift
BoutiqueMigration("v4_backfill_from_cloud") { db in
  try await BackfillService.shared.fillNotes(into: db)
}
```

Asynchronous migrations commit the tracking record separately, so the body must be idempotent.

## Helpers

| API | Use |
|---|---|
| `db.create(Schema.self)` | Run macro/schema DDL (tables, FTS, vector, MV) |
| `db.createFTSIndex(_:)` | Create a Turso Tantivy index |
| `db.createVectorIndex(_:)` | Create a Turso vector index |
| `db.createMaterializedView(_:)` | Create an incremental materialized view |
| `db.ensureColumn(...)` | Safe additive column |
| `db.syncSchema(models, policy: .additiveOnly)` | Create missing IF NOT EXISTS tables/indexes; also `ensureColumn` |

## What “auto” means here

| Allowed automatically (opt-in) | Never automatic |
|---|---|
| `CREATE TABLE/INDEX IF NOT EXISTS` via schema sync | DROP COLUMN / DROP TABLE |
| `ensureColumn` when you call it in a migration | Silent rename |
|  | Type changes |

Full model-diff auto-migration is **not** the default — it is how production data gets corrupted. Use explicit migrations for renames and data backfills.

## Turso features in migrations

Put FTS / vector / materialized view DDL in a migration (via `create` / `createFTSIndex` / macros). Gate on `db.capabilities` if the vendored lib may lack experimental flags.

See [Best practices](../best-practices) and [Turso features in Apple apps](../turso-features-in-apple-apps) for more.
