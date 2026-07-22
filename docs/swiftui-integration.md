# SwiftUI integration

BoutiqueDB is designed to feel native in SwiftUI. `BoutiqueDB` is `@MainActor`, `LiveQuery` is `@Observable`, and writes are `async`.

## Bootstrapping the database

Open the database in your app entry point before views need it. Surface open errors to the user instead of `try!`.

```swift
import BoutiqueDB
import Dependencies
import SwiftUI

@main
struct MyApp: App {
  @State private var db: BoutiqueDB?
  @State private var openError: String?

  var body: some Scene {
    WindowGroup {
      Group {
        if let openError {
          ContentUnavailableView(
            "Database error",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text(openError)
          )
        } else if let db {
          ContentView(db: db)
        } else {
          ProgressView("Opening database…")
        }
      }
      .task {
        do {
          let url = try BoutiqueDB.applicationSupportURL()
          let database = try await BoutiqueDB.open(
            url: url,
            migrations: AppMigrations.plan
          )
          prepareDependencies { $0.boutiqueDB = database }
          self.db = database
        } catch {
          openError = String(describing: error)
        }
      }
    }
  }
}
```

If you do not use `swift-dependencies`, pass the `BoutiqueDB` instance directly through the view tree or an `Environment` value.

## `@LiveQuery` in an `@Observable` model

```swift
import BoutiqueDB
import Observation
import SwiftUI

@MainActor
@Observable
final class NotesModel {
  @ObservationIgnored
  @LiveQuery(model.db) { Note.all.order { $0.updatedAt.desc() }.asSelect() }
  var notes: [Note] = []

  let db: BoutiqueDB

  init(db: BoutiqueDB) {
    self.db = db
  }

  func addNote(_ title: String) async throws {
    try await db.write { conn in
      try Note.insert { Note(id: UUID(), title: title, body: "") }
        .execute(conn.connection)
    }
  }
}
```

`@LiveQuery` is `@Observable`, so `notes` updates whenever the database changes. The query re-runs on the `DatabaseActor` and the result is assigned back on `@MainActor`.

## `@LiveQueryOne` for detail views

```swift
@MainActor
@Observable
final class NoteDetailModel {
  @ObservationIgnored
  @LiveQueryOne(model.db) { Note.where { $0.id.eq(noteID) }.asSelect() }
  var note: Note?

  init(db: BoutiqueDB, noteID: UUID) {
    self.db = db
    self.noteID = noteID
  }

  private let noteID: UUID
  private let db: BoutiqueDB

  func updateTitle(_ title: String) async throws {
    try await db.write { conn in
      try Note.where { $0.id.eq(noteID) }
        .update { $0.title = title }
        .execute(conn.connection)
    }
  }
}
```

## Dynamic query parameters

`LiveQuery.setQuery` replaces the query factory and reloads. Use this for search text, filters, or sort order.

```swift
@MainActor
@Observable
final class SearchModel {
  @ObservationIgnored
  @LiveQuery(model.db) { Note.all.asSelect() }
  var results: [Note] = []

  var query: String = "" {
    didSet {
      $results.setQuery {
        if query.isEmpty {
          Note.all.asSelect()
        } else {
          Note.where { $0.title.match(query) }.asSelect()
        }
      }
    }
  }
}
```

> **Warning:** `setQuery` is called on the `LiveQuery` projected value (`$results`), not the wrapped value.

## Loading and error states

`LiveQuery` exposes `isLoading` and `loadError`:

```swift
struct NotesView: View {
  @State private var model = NotesModel(db: …)

  var body: some View {
    Group {
      if let error = model.$notes.loadError {
        Text("Error: \(error)")
      } else if model.$notes.isLoading {
        ProgressView()
      } else {
        List(model.notes) { note in
          Text(note.title)
        }
      }
    }
  }
}
```

## Previews

Use an in-memory or temporary file with schema sync off and migrations applied inline. Never point a preview at the same file as your production app.

```swift
#Preview {
  let url = URL(fileURLWithPath: "/tmp/preview-\(UUID().uuidString).db")
  let db = try! BoutiqueDB.open(
    url: url,
    migrations: AppMigrations.plan
  )
  return NotesView(model: NotesModel(db: db))
}
```

## Sheets and navigation

Pass `BoutiqueDB` or a model object to detail and sheet views. Keep `LiveQuery` instances in the model, not in transient `View` state.

```swift
struct ContentView: View {
  @State private var model: NotesModel

  var body: some View {
    NavigationStack {
      List(model.notes) { note in
        NavigationLink(note.title) {
          NoteDetailView(db: model.db, noteID: note.id)
        }
      }
      .toolbar {
        Button("Add") {
          Task { try? await model.addNote("Untitled") }
        }
      }
    }
  }
}
```

## Best practices for SwiftUI

- Open the database once, early, and share it.
- Own `LiveQuery` instances in `@Observable` models, not in `View` bodies.
- Use `@ObservationIgnored` on `LiveQuery` properties so `Observation` observes the wrapped value, not the property wrapper itself.
- Keep closures in `write`/`read` small; do not perform UI work inside them.
- Call `db.close()` when tearing down tests or previews to avoid file locks.
