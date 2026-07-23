---
title: "Models and Tables"
sidebarTitle: "Models & Tables"
description: "Define type-safe database schemas and models in Swift using `@Table` and `@BoutiqueTable` macros."
---

BoutiqueDB leverages Point-Free's `StructuredQueries` DSL alongside custom `@BoutiqueTable` macros to map Swift structs directly to database tables.

---

## Defining `@Table` Models

Annotate your model struct with `@Table` and specify column types. `StructuredQueries` automatically generates type-safe query builders (`Note.all`, `Note.where`, `Note.insert`).

```swift Note.swift
import Foundation
import BoutiqueDB
import StructuredQueries

@Table
struct Note: Sendable {
    @Column(primaryKey: true) let id: UUID
    var title: String
    var body: String
    var isArchived: Bool
    var createdAt: Date
}
```

<ParamField path="@Column(primaryKey: true)" type="Macro Modifier">
  Marks the property as the table's Primary Key.
</ParamField>

<ParamField path="Types Supported" type="Swift Types">
  Standard Swift types automatically map to SQLite types: `String`, `Int`, `Double`, `Bool`, `Data`, `UUID`, and `Date`.
</ParamField>

---

## Turso Enhancements with `@BoutiqueTable`

When advanced database constraints or indexes are required, use `@BoutiqueTable`:

```swift UserSetting.swift
import BoutiqueDB
import StructuredQueries

@BoutiqueTable(strict: true, withoutRowID: true)
struct UserSetting: Sendable {
    @Column(primaryKey: true) var key: String
    var value: String
}
```

<CardGroup cols={2}>
  <Card title="STRICT Mode" icon="shield-check">
    Enforces strict datatype checking on SQLite columns at insertion time.
  </Card>
  <Card title="WITHOUT ROWID" icon="bolt">
    Optimizes index storage and lookups for tables with explicit primary keys.
  </Card>
</CardGroup>

---

## Type-Safe Queries

Once a model is defined, perform CRUD operations using Swift closures instead of raw SQL strings:

<CodeGroup>
```swift Insert.swift
try await db.write { conn in
    let newNote = Note(
        id: UUID(),
        title: "Grocery List",
        body: "Milk, Eggs, Bread",
        isArchived: false,
        createdAt: Date()
    )
    
    try Note.insert { newNote }.execute(conn.connection)
}
```

```swift Query.swift
let activeNotes = try await db.read { conn in
    try Note.where { $0.isArchived.eq(false) }
        .order { $0.createdAt.desc() }
        .fetchAll(conn.connection)
}
```

```swift Update.swift
try await db.write { conn in
    try Note.where { $0.id.eq(targetId) }
        .update { $0.isArchived.set(true) }
        .execute(conn.connection)
}
```

```swift Delete.swift
try await db.write { conn in
    try Note.where { $0.id.eq(targetId) }
        .delete()
        .execute(conn.connection)
}
```
</CodeGroup>

<Tip>
**Compile-Time Safety**: If a model property name changes or type changes, Xcode catches query mismatches during project compilation!
</Tip>
