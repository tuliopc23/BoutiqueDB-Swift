---
title: "Core Concepts"
sidebarTitle: "Core Concepts"
description: "Understand the core building blocks of BoutiqueDB: database files, models, migrations, actor concurrency, live queries, and sync."
---

BoutiqueDB is organized around a small number of core concepts. Understanding them makes integrating the framework into your iOS or macOS application straightforward.

<CardGroup cols={2}>
  <Card title="Database Sandbox File" icon="file-zipper">
    SQLite-compatible database file residing inside your app container or shared App Group.
  </Card>
  <Card title="Type-Safe Models" icon="code">
    Swift structs using `@Table` and `@BoutiqueTable` macros with `StructuredQueries`.
  </Card>
  <Card title="DatabaseActor Concurrency" icon="shield-halved">
    All engine I/O runs safely off the main thread via `@MainActor` and background actors.
  </Card>
  <Card title="CDC Live Queries" icon="rotate">
    Automated UI state updates backed by Change Data Capture tokens.
  </Card>
</CardGroup>

---

## 1. The Database File

A BoutiqueDB database is a regular SQLite-compatible file on disk. You select its location using helper methods:

```swift
let url = try BoutiqueDB.applicationSupportURL(filename: "app.db")
let db = try await BoutiqueDB.open(url: url, migrations: AppMigrations.plan)
```

<ParamField path="url" type="URL" required>
  Target disk URL. Supported locations include:
  - `BoutiqueDB.applicationSupportURL()`: Default persistent data sandbox.
  - `BoutiqueDB.documentsURL()`: User-accessible documents directory.
  - `BoutiqueDB.inMemoryURL()`: In-memory store for Xcode Previews and tests.
  - App Group Container: Shared database file when `multiProcess: true` is set.
</ParamField>

---

## 2. Models (`@Table` and `@BoutiqueTable`)

Models are standard Swift structs. `StructuredQueries` provides `@Table` for type-safe query generation, while BoutiqueDB provides `@BoutiqueTable` for Turso-specific table options.

<CodeGroup>
```swift StandardTable.swift
import StructuredQueries

@Table
struct Note: Sendable {
    @Column(primaryKey: true) let id: UUID
    var title: String
    var body: String
    var updatedAt: Date = Date()
}
```

```swift BoutiqueEnhancedTable.swift
import BoutiqueDB
import StructuredQueries

@BoutiqueTable(strict: true, withoutRowID: true)
struct Setting: Sendable {
    @Column(primaryKey: true) var key: String
    var value: String
}
```
</CodeGroup>

<Note>
**Model Capabilities**: `@Table` exposes `Note.all`, `Note.where { ... }`, `Note.insert`, `Note.update`, and `Codable` decoding. `@BoutiqueTable` adds `STRICT`, `WITHOUT ROWID`, and generated columns.
</Note>

---

## 3. Schema Migrations

Migrations in BoutiqueDB are explicit, named, and append-only:

```swift
enum AppMigrations {
    static let plan = BoutiqueMigrationPlan {
        BoutiqueMigration("v1_create_notes") { conn in
            try conn.execute("""
                CREATE TABLE note (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
        }

        BoutiqueMigration("v2_add_pinned_column") { conn in
            try conn.execute("""
                ALTER TABLE note ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0
            """)
        }
    }
}
```

---

## 4. Isolation & Concurrency Safety

All database read and write operations are routed through isolation guards:

```swift
// Write Transaction
try await db.write { conn in
    try Note.insert { Note(id: UUID(), title: "New Note", body: "") }
        .execute(conn.connection)
}

// Read Query
let notes = try await db.read { conn in
    try Note.all.order { $0.updatedAt.desc() }.fetchAll(conn.connection)
}
```

<Warning>
**Actor Isolation**: `BoutiqueDB` itself is annotated with `@MainActor` so it can be safely owned by SwiftUI views. All heavy disk and engine I/O runs on a dedicated background `DatabaseActor`.
</Warning>

---

## 5. CDC Live Queries

`LiveQuery` and `LiveQueryOne` property wrappers subscribe to database change tokens (`turso_cdc`) and trigger view invalidation automatically:

```swift
@MainActor
final class NotesModel: ObservableObject {
    @LiveQuery(db) { Note.all.order { $0.updatedAt.desc() }.asSelect() }
    var notes: [Note] = []
}
```

---

## 6. Error Handling

BoutiqueDB surfaces strongly-typed errors via `BoutiqueError`:

```swift
do {
    try await db.write { conn in ... }
} catch let error as BoutiqueError {
    switch error {
    case .sql(let code, let message):
        print("SQLite/Turso Engine Error (\(code)): \(message)")
    case .migrationFailed(let id, let message):
        print("Migration '\(id)' failed: \(message)")
    case .transactionInProgress:
        print("Write conflict occurred.")
    default:
        print("BoutiqueDB Error: \(error)")
    }
}
```
