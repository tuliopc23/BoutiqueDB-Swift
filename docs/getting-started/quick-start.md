# Quick start

This guide opens a local database, runs a migration, inserts data, and observes it from SwiftUI.

## 1. Define a model

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

## 2. Write a migration plan

```swift
import BoutiqueDB

enum AppMigrations {
  static let plan = BoutiqueMigrationPlan {
    BoutiqueMigration(1) { db in
      try await db.create(Note.self)
    }
  }
}
```

## 3. Open the database

```swift
import BoutiqueDB

let url = try BoutiqueDB.applicationSupportURL()
let db = try await BoutiqueDB.open(
  url: url,
  migrations: AppMigrations.plan
)
```

`BoutiqueDB.open` uses the `.tursoEnhanced` open options by default, which enables `views`, `index_method`, `generated_columns`, `vacuum`, and `without_rowid`.

## 4. Read and write

```swift
try await db.write { conn in
  try conn.execute(
    "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
    [.text(UUID().uuidString), .text("Hello"), .text("")]
  )
}

let notes = try await db.read { conn in
  try Note.all.order { $0.updatedAt.desc() }.fetchAll(conn)
}
```

## 5. Observe in SwiftUI

```swift
import SwiftUI
import BoutiqueDB

@MainActor
final class NotesModel: Observable {
  let db = try! BoutiqueDB(
    url: BoutiqueDB.applicationSupportURL(),
    migrations: AppMigrations.plan
  )

  @LiveQuery(db) { Note.all.order { $0.updatedAt.desc() }.asSelect() }
  var notes: [Note] = []

  func addNote(title: String) async throws {
    try await db.write { conn in
      try Note.insert { Note(id: UUID(), title: title, body: "") }
        .execute(conn)
    }
  }
}

struct NotesView: View {
  @State private var model = NotesModel()

  var body: some View {
    List(model.notes) { note in
      Text(note.title)
    }
  }
}
```

`@LiveQuery` refreshes automatically when local changes are committed.

## Next steps

- [Open options](open-options)
- [Models and tables](guides/models-and-tables)
- [Live queries](guides/live-queries)
- [CloudKit sync](guides/cloudkit-sync)
