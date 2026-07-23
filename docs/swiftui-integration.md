---
title: "SwiftUI Integration"
sidebarTitle: "SwiftUI Integration"
description: "Master reactive state management, `@LiveQuery`, `@LiveQueryOne`, and Xcode Previews in SwiftUI apps."
---

BoutiqueDB is built specifically for modern Swift and SwiftUI. It combines `@MainActor` thread safety with `@LiveQuery` property wrappers to deliver effortless reactive state updates.

## Observing Database State in SwiftUI

`BoutiqueDB` provides two dedicated property wrappers for observing queries in real time:

- `@LiveQuery`: Observes an array of models matching a `StructuredQueries` expression.
- `@LiveQueryOne`: Observes a single optional model matching a unique query (e.g. by Primary Key).

---

### `@LiveQuery` Example

```swift TaskListView.swift
import SwiftUI
import BoutiqueDB
import StructuredQueries

struct TaskListView: View {
    let db: BoutiqueDB

    @ObservationIgnored
    @LiveQuery var tasks: [TaskItem]

    init(db: BoutiqueDB) {
        self.db = db
        self._tasks = LiveQuery(db) {
            TaskItem.where { $0.isCompleted.eq(false) }
                .order { $0.createdAt.desc() }
                .asSelect()
        }
    }

    var body: some View {
        List(tasks, id: \.id) { task in
            Text(task.title)
        }
    }
}
```

---

### `@LiveQueryOne` Example

```swift TaskDetailView.swift
import SwiftUI
import BoutiqueDB
import StructuredQueries

struct TaskDetailView: View {
    let db: BoutiqueDB
    let taskId: UUID

    @ObservationIgnored
    @LiveQueryOne var task: TaskItem?

    init(db: BoutiqueDB, taskId: UUID) {
        self.db = db
        self.taskId = taskId
        self._task = LiveQueryOne(db) {
            TaskItem.where { $0.id.eq(taskId) }.asSelect()
        }
    }

    var body: some View {
        VStack {
            if let task {
                Text(task.title).font(.largeTitle)
                Text("Created on: \(task.createdAt.formatted())")
            } else {
                ContentUnavailableView("Task Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }
}
```

---

## Dynamic Query Parameterization

If your query depends on user selection or view parameters, initialize `@LiveQuery` inside your custom initializer:

<CodeGroup>
```swift SearchableListView.swift
struct SearchableListView: View {
    let db: BoutiqueDB
    @State private var searchQuery = ""
    
    var body: some View {
        VStack {
            TextField("Search tasks...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            SearchResultsView(db: db, query: searchQuery)
        }
    }
}
```

```swift SearchResultsView.swift
struct SearchResultsView: View {
    @ObservationIgnored
    @LiveQuery var results: [TaskItem]
    
    init(db: BoutiqueDB, query: String) {
        self._results = LiveQuery(db) {
            if query.isEmpty {
                return TaskItem.order { $0.title }.asSelect()
            } else {
                return TaskItem.where { $0.title.contains(query) }.asSelect()
            }
        }
    }
    
    var body: some View {
        List(results, id: \.id) { item in
            Text(item.title)
        }
    }
}
```
</CodeGroup>

---

## Xcode Previews Setup

BoutiqueDB includes an in-memory database helper (`BoutiqueDB.inMemoryURL()`) designed specifically for Xcode Previews and Unit Tests.

```swift ContentView_Previews.swift
#Preview {
    let db = try! BoutiqueDB.open(
        url: BoutiqueDB.inMemoryURL(),
        migrations: AppMigrations.plan
    )
    
    // Seed initial preview data asynchronously
    Task {
        try await db.write { conn in
            try TaskItem.insert {
                TaskItem(id: UUID(), title: "Design Landing Page", isCompleted: false, createdAt: Date())
                TaskItem(id: UUID(), title: "Set up Mintlify Docs", isCompleted: true, createdAt: Date())
            }.execute(conn.connection)
        }
    }
    
    return TaskListView(db: db)
}
```

<Tip>
**Performance Best Practice**: Keep `@LiveQuery` definitions scoped to the specific views that require them. Because BoutiqueDB CDC tracks changes per table, views only re-render when relevant tables undergo mutation!
</Tip>
