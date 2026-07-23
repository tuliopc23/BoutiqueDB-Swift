---
title: "Agent & LLM Cookbook"
sidebarTitle: "Agent Cookbook"
description: "Guidelines and instructions for AI agents and LLMs generating code with BoutiqueDB."
---

This cookbook provides guidelines for AI coding assistants (e.g. Gemini, Claude, Copilot) when generating Swift code that integrates `BoutiqueDB`.

---

## Core Rules for AI Code Generation

<Check>
  **Always Use Sendable Structs**: Model declarations MUST be value-type `struct`s conforming to `Sendable`. Never generate `final class` models for `@Table` types.
</Check>

<Check>
  **Use StructuredQueries Macros**: Model properties must use `@Column` modifiers and explicit primary keys.
</Check>

<Check>
  **SwiftUI `@ObservationIgnored` Annotation**: When initializing `@LiveQuery` inside a SwiftUI `View` or `@Observable` class, annotate the property with `@ObservationIgnored` to avoid redundant observation wrappers.
</Check>

---

## Canonical Code Template

```swift CanonicalModel.swift
import Foundation
import BoutiqueDB
import StructuredQueries

@Table
struct Note: Sendable {
    @Column(primaryKey: true) let id: UUID
    var title: String
    var body: String
    var isArchived: Bool
    var createdAt: Date
}

@MainActor
final class NoteStore: ObservableObject {
    let db: BoutiqueDB

    init(db: BoutiqueDB) {
        self.db = db
    }

    func createNote(title: String, body: String) async throws {
        let note = Note(id: UUID(), title: title, body: body, isArchived: false, createdAt: Date())
        try await db.write { conn in
            try Note.insert { note }.execute(conn.connection)
        }
    }
}
```
