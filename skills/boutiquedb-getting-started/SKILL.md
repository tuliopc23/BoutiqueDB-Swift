---
name: boutiquedb-getting-started
description: |
  Helps users install BoutiqueDB, run the first migration, insert data, choose open options, and integrate with SwiftUI.
  Use when the user says "how do I install BoutiqueDB", "quick start", "getting started",
  "BoutiqueDB open options", "BoutiqueDB SPM", or "BoutiqueDB first model".
---

# BoutiqueDB getting started

Guide the user through installing BoutiqueDB-Swift via Swift Package Manager, opening a database, running migrations, performing reads and writes, and wiring a `LiveQuery` to SwiftUI.

## Trigger phrases

- "install BoutiqueDB"
- "BoutiqueDB quick start"
- "how do I open BoutiqueDB"
- "BoutiqueDB SPM"
- "BoutiqueDB open options"
- "BoutiqueDB first model"

## Workflow

1. **Check requirements**: iOS 17+ / macOS 14+, Swift 6.1+, Xcode 16+.
2. **Provide the Package.swift snippet**:
   ```swift
   .package(
     url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git",
     exact: "0.3.0-beta.1"
   )
   ```
3. **Show a complete quick-start example**:
   ```swift
   import BoutiqueDB
   import Observation
   import StructuredQueries
   import SwiftUI

   @Table
   struct Note: Sendable {
     @Column(primaryKey: true) let id: UUID
     var title: String
     var body: String
   }

   enum AppMigrations {
     static let plan = BoutiqueMigrationPlan {
       BoutiqueMigration("v1_create_notes") { conn in
         for sql in Note.boutiqueCreateStatements {
           try conn.execute(sql)
         }
       }
     }
   }

   @main
   struct MyApp: App {
     @State private var db: BoutiqueDB?

     var body: some Scene {
       WindowGroup {
         if let db {
           NotesView(model: NotesModel(db: db))
         } else {
           ProgressView("Opening…")
         }
       }
       .task {
         do {
           let url = try BoutiqueDB.applicationSupportURL()
           self.db = try await BoutiqueDB.open(url: url, migrations: AppMigrations.plan)
         } catch {
           // surface error in real app
         }
       }
     }
   }

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

   struct NotesView: View {
     @State var model: NotesModel
     var body: some View {
       List(model.notes) { note in Text(note.title) }
         .toolbar {
           Button("Add") { Task { try? await model.addNote("Untitled") } }
         }
     }
   }
   ```
4. **Explain `TursoOpenOptions`**: default `.tursoEnhanced`, `.tursoEnhancedAsync` for cooperative async I/O, plus `multiProcess`, `encryption`.
5. **Reference docs**:
   - `docs/getting-started/installation.md`
   - `docs/getting-started/quick-start.md`
   - `docs/getting-started/open-options.md`
   - `docs/core-concepts.md`
   - `docs/swiftui-integration.md`
