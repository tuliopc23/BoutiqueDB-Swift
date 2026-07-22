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

enum NotesSchema: BoutiqueSchema {
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
}

enum AppMigrations {
  static let plan = BoutiqueMigrationPlan {
    BoutiqueMigration("v1_notes") { db in
      try await db.create(NotesSchema.self)
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

  var body: some View {
    List {
      ForEach(model?.notes ?? [], id: \.id) { note in
        Text(note.title)
      }
    }
    .task {
      model = NotesModel(db: db)
    }
    .toolbar {
      Button("Add") {
        Task { try? await model?.add("Untitled") }
      }
    }
  }
}
```

## Sync (optional)

```swift
let sync = try BoutiqueDBSyncEngine(
  db: db,
  syncedTables: [SyncedTable(name: "notes", columns: ["title", "body"])],
  enablesCloudKit: true
)
try sync.start()
sync.attach(to: db, automaticallyDrain: true)
```
