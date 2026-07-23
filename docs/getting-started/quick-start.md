---
title: "Quick Start"
sidebarTitle: "Quick Start"
description: "Build a complete reactive Swift application with BoutiqueDB, @Table models, and LiveQuery in 5 minutes."
---

Follow this step-by-step guide to get up and running with BoutiqueDB in your Swift app.

<Steps>
  <Step title="Define your @Table Model">
    Create a type-safe database model using `StructuredQueries`. `BoutiqueDB` models map directly to SQLite tables.

    ```swift TaskItem.swift
    import Foundation
    import BoutiqueDB
    import StructuredQueries

    @Table
    struct TaskItem {
        @Column(primaryKey: true) let id: UUID
        var title: String
        var isCompleted: Bool
        var createdAt: Date
    }
    ```
  </Step>

  <Step title="Define Database Migrations">
    BoutiqueDB uses append-only migrations to manage your schema safely over time.

    ```swift Migrations.swift
    import BoutiqueDB

    enum AppMigrations {
        static let plan = MigrationPlan([
            Migration(name: "v1_create_tasks") { conn in
                try conn.execute("""
                    CREATE TABLE task_item (
                        id TEXT PRIMARY KEY NOT NULL,
                        title TEXT NOT NULL,
                        isCompleted INTEGER NOT NULL DEFAULT 0,
                        createdAt REAL NOT NULL
                    )
                """)
            }
        ])
    }
    ```
  </Step>

  <Step title="Initialize BoutiqueDB Actor">
    Initialize your database instance on `@MainActor` during app startup.

    ```swift AppStore.swift
    import Foundation
    import BoutiqueDB

    @MainActor
    final class AppStore: ObservableObject {
        let db: BoutiqueDB

        init() {
            let storeURL = BoutiqueDB.applicationSupportURL().appendingPathComponent("tasks.sqlite")
            self.db = try! BoutiqueDB.open(
                url: storeURL,
                migrations: AppMigrations.plan
            )
        }

        func addTask(title: String) async throws {
            let task = TaskItem(id: UUID(), title: title, isCompleted: false, createdAt: Date())
            try await db.write { conn in
                try TaskItem.insert { task }.execute(conn.connection)
            }
        }

        func toggleTask(_ task: TaskItem) async throws {
            try await db.write { conn in
                try TaskItem.where { $0.id.eq(task.id) }
                    .update { $0.isCompleted.set(!task.isCompleted) }
                    .execute(conn.connection)
            }
        }
    }
    ```
  </Step>

  <Step title="Bind Live Queries to SwiftUI">
    Use `@LiveQuery` inside your SwiftUI views to receive real-time updates as underlying database rows change.

    ```swift TaskListView.swift
    import SwiftUI
    import BoutiqueDB
    import StructuredQueries

    struct TaskListView: View {
        @StateObject private var store = AppStore()
        @State private var newTitle = ""

        @ObservationIgnored
        @LiveQuery var tasks: [TaskItem]

        init() {
            let store = AppStore()
            self._store = StateObject(wrappedValue: store)
            self._tasks = LiveQuery(store.db) {
                TaskItem.order { $0.createdAt.desc() }.asSelect()
            }
        }

        var body: some View {
            NavigationStack {
                List {
                    Section("New Task") {
                        HStack {
                            TextField("Task Title", text: $newTitle)
                            Button("Add") {
                                Task {
                                    try? await store.addTask(title: newTitle)
                                    newTitle = ""
                                }
                            }
                            .disabled(newTitle.isEmpty)
                        }
                    }

                    Section("Your Tasks") {
                        ForEach(tasks, id: \.id) { task in
                            HStack {
                                Text(task.title)
                                Spacer()
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isCompleted ? .green : .gray)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task {
                                    try? await store.toggleTask(task)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("BoutiqueDB Tasks")
            }
        }
    }
    ```
  </Step>
</Steps>

<Tip>
**What's Happening Under the Hood?** When you write to `db.write`, BoutiqueDB records tiny Change Data Capture (CDC) events (`turso_cdc`). `@LiveQuery` listens for CDC change tokens and updates your SwiftUI view instantly (< 250ms latency) without full-table reloads!
</Tip>
