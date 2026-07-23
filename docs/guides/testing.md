---
title: "Testing & Previewing"
sidebarTitle: "Testing"
description: "Write fast, isolated unit tests and configure Xcode Previews with BoutiqueDB in-memory databases."
---

BoutiqueDB provides built-in utilities for creating isolated, temporary in-memory database instances designed for unit testing and Xcode Previews.

---

## Xcode Previews Setup

Use `BoutiqueDB.inMemoryURL()` to launch lightweight, fast database instances without writing temporary files to the disk sandbox:

```swift TaskListView_Previews.swift
import SwiftUI
import BoutiqueDB

#Preview {
    let db = try! BoutiqueDB.open(
        url: BoutiqueDB.inMemoryURL(),
        migrations: AppMigrations.plan
    )
    
    Task {
        try await db.write { conn in
            try TaskItem.insert {
                TaskItem(id: UUID(), title: "Test Preview Task", isCompleted: false, createdAt: Date())
            }.execute(conn.connection)
        }
    }
    
    return TaskListView(db: db)
}
```

---

## Writing XCTest Unit Tests

Create fresh in-memory instances inside `setUp()` or helper methods to ensure complete test isolation:

```swift TaskStoreTests.swift
import XCTest
import BoutiqueDB
@testable import MyApp

final class TaskStoreTests: XCTestCase {
    var db: BoutiqueDB!

    override func setUp() async throws {
        try await super.setUp()
        self.db = try BoutiqueDB.open(
            url: BoutiqueDB.inMemoryURL(),
            migrations: AppMigrations.plan
        )
    }

    func testAddTaskInsertsRecord() async throws {
        let task = TaskItem(id: UUID(), title: "Buy Milk", isCompleted: false, createdAt: Date())
        
        try await db.write { conn in
            try TaskItem.insert { task }.execute(conn.connection)
        }
        
        let fetched = try await db.read { conn in
            try TaskItem.where { $0.id.eq(task.id) }.fetchOne(conn.connection)
        }
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Buy Milk")
    }
}
```

<Tip>
**In-Memory Speed**: `inMemoryURL()` runs database operations in RAM, making XCTest execution instant while verifying full SQL schema and migration plans!
</Tip>
