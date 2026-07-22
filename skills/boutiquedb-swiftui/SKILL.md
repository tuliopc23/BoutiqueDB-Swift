---
name: boutiquedb-swiftui
description: |
  Guides SwiftUI integration with BoutiqueDB: @Observable models, @LiveQuery, @LiveQueryOne,
  previews, forms, dependency injection, and common UI patterns.
  Use when the user asks about "BoutiqueDB SwiftUI", "LiveQuery SwiftUI", "@Observable BoutiqueDB",
  "BoutiqueDB preview", or "BoutiqueDB UI".
---

# BoutiqueDB SwiftUI integration

Guide the user through wiring BoutiqueDB into SwiftUI with `@Observable` models, `@LiveQuery`, `@LiveQueryOne`, previews, and dependency injection.

## Trigger phrases

- "BoutiqueDB SwiftUI"
- "LiveQuery SwiftUI"
- "@Observable BoutiqueDB"
- "BoutiqueDB preview"
- "BoutiqueDB UI"
- "BoutiqueDB SwiftUI integration"

## Workflow

1. **Bootstrap in `App` or scene**:
   - Open `BoutiqueDB` in a `.task` modifier.
   - Surface open errors instead of `try!`.
   - Pass the `BoutiqueDB` instance to the root view or register with `swift-dependencies`.
2. **Model with `@Observable` and `LiveQuery`**:
   ```swift
   @MainActor
   @Observable
   final class NotesModel {
     @ObservationIgnored
     @LiveQuery(db) { Note.all.asSelect() }
     var notes: [Note] = []

     let db: BoutiqueDB
     init(db: BoutiqueDB) { self.db = db }

     func addNote(_ title: String) async throws {
       try await db.write { conn in
         try Note.insert { Note(id: UUID(), title: title, body: "") }
           .execute(conn.connection)
       }
     }
   }
   ```
3. **Single-row screens with `@LiveQueryOne`**:
   ```swift
   @ObservationIgnored
   @LiveQueryOne(db) { Note.where { $0.id.eq(noteID) }.asSelect() }
   var note: Note?
   ```
4. **Dynamic search**:
   - Use `model.$results.setQuery { ... }` to swap the query when search text changes.
   - Use `.match(query)` and `.score(query)` for FTS-backed search.
5. **Loading and error states**:
   - Check `$liveQuery.isLoading` and `$liveQuery.loadError`.
6. **Previews**:
   - Use a temporary database file per preview.
   - Apply migrations inline; never point previews at production data.
7. **Common anti-patterns to reject**:
   - Creating `LiveQuery` inside `View.body` instead of an `@Observable` model.
   - Forgetting `@ObservationIgnored` on the `LiveQuery` property.
   - Calling `BoutiqueDB` methods inside `read`/`write` closures.
8. **Reference docs**:
   - `docs/swiftui-integration.md`
   - `docs/guides/live-queries.md`
   - `docs/best-practices.md`
