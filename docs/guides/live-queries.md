# Live queries

Live queries keep SwiftUI in sync with the local database. They observe CDC change records and refresh the query result automatically.

## How it works

1. Local writes call `TursoStore.invalidate()`, which increments a generation.
2. `TursoStore` publishes an `AsyncStream` of change events.
3. `@LiveQuery` subscribes to the stream and re-runs its query on the `DatabaseActor`.
4. The wrapped property updates, and SwiftUI re-renders.

CDC polling is cooperative (~50 ms idle) and does not require push notifications.

## `@LiveQuery`

```swift
import BoutiqueDB
import Observation
import SwiftUI

@MainActor
@Observable
final class NotesModel {
  @ObservationIgnored
  @LiveQuery(db) { Note.all.order { $0.updatedAt.desc() }.asSelect() }
  var notes: [Note] = []

  let db: BoutiqueDB
  init(db: BoutiqueDB) { self.db = db }
}
```

> **Note:** Use `@ObservationIgnored` on the property wrapper so `Observation` tracks `notes`, not the wrapper instance.

## `@LiveQueryOne`

For a single row:

```swift
@ObservationIgnored
@LiveQueryOne(db) { Note.where { $0.id.eq(noteID) }.asSelect() }
var note: Note?
```

## Dynamic queries

```swift
@MainActor
@Observable
final class SearchModel {
  @ObservationIgnored
  @LiveQuery(db) { Note.all.asSelect() }
  var results: [Note] = []

  var query = "" {
    didSet {
      $results.setQuery {
        if query.isEmpty {
          Note.all.asSelect()
        } else {
          Note.where { $0.title.match(query) }
            .order { $0.title.score(query).desc() }
            .asSelect()
        }
      }
    }
  }
}
```

## Manual refresh

You can force a refresh when the stream is not enough:

```swift
model.$notes.forceRefresh()

// Awaitable reload
await model.$notes.load()
```

## Loading and error states

```swift
struct NotesView: View {
  @State private var model: NotesModel

  var body: some View {
    if let error = model.$notes.loadError {
      Text("Error: \(error)")
    } else if model.$notes.isLoading {
      ProgressView()
    } else {
      List(model.notes) { note in Text(note.title) }
    }
  }
}
```

## Performance notes

- Each `LiveQuery` runs its SQL on the `DatabaseActor` whenever a change is detected.
- For large result sets, use `limit` and `order` to keep refresh work small.
- Avoid creating many `LiveQuery` instances for the same underlying data; share a model object across views.

See also [SwiftUI integration](../swiftui-integration) and [Performance tuning](../performance-tuning).
