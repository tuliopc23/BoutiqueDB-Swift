---
title: "Concurrency & Thread Safety"
sidebarTitle: "Concurrency"
description: "Master Swift concurrency isolation, DatabaseActor execution, transaction locks, and background writes in BoutiqueDB."
---

BoutiqueDB is architected around modern Swift concurrency (`async`/`await`, `@MainActor`, `Sendable`, and `Actor` isolation) to eliminate data races and `SQLITE_BUSY` crashes.

---

## Isolation Architecture

```mermaid
flowchart TD
    UI[@MainActor UI Layer / SwiftUI] -->|async db.read / db.write| Actor[DatabaseActor Background Context]
    Actor -->|Isolated SQLite Handle| TursoEngine[(Turso C Engine / Storage)]
```

- **`BoutiqueDB` Container**: Annotated with `@MainActor`. You can store reference instances in your App State, `@StateObject`, or `@Observable` models.
- **`DatabaseActor`**: Isolated actor where all disk reads, SQL compilation, and writes take place.

---

## Read vs Write Isolation Rules

<CardGroup cols={2}>
  <Card title="db.read Closure" icon="book-open">
    Provides a read-only `BoutiqueDBConnection`. Safe to run concurrent reads simultaneously across threads.
  </Card>
  <Card title="db.write Closure" icon="pen-to-square">
    Provides an exclusive write transaction. Automatically manages `BEGIN` and `COMMIT`/`ROLLBACK`.
  </Card>
</CardGroup>

```swift ConcurrencyExample.swift
// Execute write on background actor
try await db.write { conn in
    try Note.insert { newNote }.execute(conn.connection)
}

// Execute read on background actor
let notes = try await db.read { conn in
    try Note.all.fetchAll(conn.connection)
}
```

---

## Best Practices for Concurrency

<Check>
  **Do**: Pass value-type models (`Sendable` structs) in and out of `db.read` and `db.write` closures.
</Check>

<Warning>
  **Don't**: Capture mutable state from outside the closure or call `@MainActor` methods from inside a `db.write` block. Doing so causes thread safety deadlocks.
</Warning>
