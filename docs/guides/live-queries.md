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
import SwiftUI

@MainActor
final class NotesModel: Observable {
  let db = try! BoutiqueDB(
    url: BoutiqueDB.applicationSupportURL(),
    migrations: AppMigrations.plan
  )

  @LiveQuery(db) { Note.all.order { $0.updatedAt.desc() }.asSelect() }
  var notes: [Note] = []
}
```

## `@LiveQueryOne`

For a single row:

```swift
@LiveQueryOne(db) { Note.where { $0.id.eq(noteID) }.asSelect() }
var note: Note?
```

## Manual refresh

You can force a refresh when the stream is not enough:

```swift
model.$notes.forceRefresh()
```

## Performance notes

- Each `LiveQuery` runs its SQL on the `DatabaseActor` whenever a change is detected.
- For large result sets, use `limit` and `order` to keep refresh work small.
- Avoid creating many `LiveQuery` instances for the same underlying data; share a model object across views.

## CDC and MVCC

CDC is enabled on the primary handle. If you use `concurrentWrites`, BoutiqueDB either uses MVCC on a separate writer or falls back to busy-retry immediate transactions, so CDC is never silent.
