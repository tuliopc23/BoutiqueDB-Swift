# Copy-paste app template (no SampleApp target)

Open the database **before** views that need `@Dependency(\.boutiqueDB)` or a model.
Do not use `try!` in production UI — surface open failures.

```swift
import BoutiqueDB
import Dependencies
import StructuredQueries
import SwiftUI

@Table
struct Note: Sendable {
  @Column(primaryKey: true) let id: String
  var title: String
  var body: String
}

enum NotesSchema: BoutiqueSchemaColumns {
  static var boutiqueTableName: String { "notes" }
  static var boutiqueCreateStatements: [String] {
    ["""
     CREATE TABLE IF NOT EXISTS "notes" (
       "id" TEXT PRIMARY KEY NOT NULL,
       "title" TEXT NOT NULL,
       "body" TEXT NOT NULL
     )
     """]
  }
  static var boutiqueColumns: [BoutiqueColumnSpec] {
    [
      BoutiqueColumnSpec(name: "id", sqlType: "TEXT", isNullable: false, isPrimaryKey: true),
      BoutiqueColumnSpec(name: "title", sqlType: "TEXT", isNullable: false),
      BoutiqueColumnSpec(name: "body", sqlType: "TEXT", isNullable: false),
    ]
  }
}

enum AppMigrations {
  static let plan = BoutiqueMigrationPlan {
    BoutiqueMigration("v1_notes") { connection in
      for statement in NotesSchema.boutiqueCreateStatements {
        try connection.execute(statement)
      }
    }
  }
}

@main
struct MyApp: App {
  @State private var openError: String?
  @State private var ready = false

  var body: some Scene {
    WindowGroup {
      Group {
        if let openError {
          ContentUnavailableView(
            "Database error",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text(openError)
          )
        } else if ready {
          ContentView()
        } else {
          ProgressView("Opening database…")
        }
      }
      .task {
        do {
          let url = try BoutiqueDB.applicationSupportURL()
          let db = try await BoutiqueDB.open(url: url, migrations: AppMigrations.plan)
          prepareDependencies { $0.boutiqueDB = db }
          ready = true
        } catch {
          openError = String(describing: error)
        }
      }
    }
  }
}

@MainActor
@Observable
final class NotesModel {
  let db: BoutiqueDB
  @ObservationIgnored private let live: LiveQuery<Note>
  var notes: [Note] { live.wrappedValue }

  init(db: BoutiqueDB) {
    self.db = db
    self.live = LiveQuery(db) { Note.all.asSelect() }
  }

  func add(_ title: String) async throws {
    let id = UUID().uuidString
    try await db.write { conn in
      try conn.execute(
        "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
        [.text(id), .text(title), .text("")]
      )
    }
  }
}

struct ContentView: View {
  @Dependency(\.boutiqueDB) var db
  @State private var model: NotesModel?
  @State private var addError: String?

  var body: some View {
    List {
      ForEach(model?.notes ?? [], id: \.id) { note in
        Text(note.title)
      }
    }
    .alert("Could not add note", isPresented: .constant(addError != nil)) {
      Button("OK") { addError = nil }
    } message: {
      Text(addError ?? "Unknown database error")
    }
    .task {
      model = NotesModel(db: db)
    }
    .toolbar {
      Button("Add") {
        Task {
          do {
            try await model?.add("Untitled")
          } catch {
            addError = String(describing: error)
          }
        }
      }
    }
  }
}
```

## Sync (optional)

```swift
let sync = try BoutiqueDBSyncEngine(
  db: db,
  syncedTables: [try SyncedTable(schema: NotesSchema.self)],
  enablesCloudKit: true
)
try await sync.start()
sync.attach(to: db, automaticallyDrain: true)
```
