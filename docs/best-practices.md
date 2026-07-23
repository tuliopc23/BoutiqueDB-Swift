---
title: "Best Practices"
sidebarTitle: "Best Practices"
description: "Recommended architectural patterns, error handling strategies, and schema design guidelines for BoutiqueDB apps."
---

Follow these guidelines to build fast, maintainable, and reliable iOS and macOS apps using BoutiqueDB.

---

## Schema & Model Design

<Check>
  **Use Immutable Struct Models**: Define `@Table` models as `Sendable` value-type structs (`struct Note: Sendable`). Avoid mutable reference classes to eliminate concurrency data races.
</Check>

<Check>
  **Explicit Primary Keys**: Always specify an explicit primary key via `@Column(primaryKey: true)`. Prefer `UUID` or `String` keys for seamless CloudKit synchronization.
</Check>

<Check>
  **Append-Only Migrations**: Give every migration step a descriptive, versioned name (`"v1_create_notes"`, `"v2_add_tags"`). Never modify existing migration strings after app release.
</Check>

---

## Performance & Query Ergonomics

<Tip>
  **Perform Batch Inserts**: Group multi-row insertions inside a single `db.write` transaction instead of invoking multiple `db.write` blocks in a loop.
</Tip>

```swift BatchInsert.swift
// Recommended: Single Transaction Batch Write
try await db.write { conn in
    for item in itemsToInsert {
        try Item.insert { item }.execute(conn.connection)
    }
}
```

<Warning>
  **Avoid Large Blobs**: Avoid storing multi-megabyte binary files directly in database columns. Store media files in the `Documents` directory and persist relative file paths in SQLite.
</Warning>

---

## SwiftUI State Management

- Keep `@LiveQuery` definitions scoped to the child views that require them.
- Avoid passing raw SQL connection objects across view boundaries.
- Use `BoutiqueDB.inMemoryURL()` for SwiftUI Previews and unit tests.
