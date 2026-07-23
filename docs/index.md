---
title: "BoutiqueDB for Swift"
sidebarTitle: "Overview"
description: "Local-first persistence for iOS and macOS built on the Turso database engine with CloudKit sync, CDC live queries, and modern Swift concurrency."
---

<p align="center">
  <img src="/logo/light.png" alt="BoutiqueDB Logo" width="160" />
</p>

## Modern Swift Persistence for Apple Platforms

**BoutiqueDB** brings SQLiteData ergonomics, Change Data Capture (CDC) live queries, and opportunistic CloudKit sync to Swift developers. Built on top of the native Rust **Turso engine** via `sdk-kit`, it empowers your Apple apps with local-first reliability and opt-in Turso capabilities like full-text search, vector embeddings, and concurrent writes.

<CardGroup cols={2}>
  <Card title="Local-First Engine" icon="database" href="/core-concepts">
    SQLite-compatible local storage running directly inside the app sandbox with `@MainActor` thread safety.
  </Card>
  <Card title="Reactive CDC Live Queries" icon="bolt" href="/guides/live-queries">
    UI components update automatically with `@LiveQuery` and `@LiveQueryOne` via change tokens.
  </Card>
  <Card title="CloudKit Synchronization" icon="cloud-arrow-up" href="/guides/cloudkit-sync">
    Zero-backend private database sync using Apple's native `CKSyncEngine`.
  </Card>
  <Card title="Turso Superpowers" icon="wand-magic-sparkles" href="/turso-features-in-apple-apps">
    Opt-in access to Tantivy FTS, dense/sparse vector search, IVM materialized views, and AEGIS encryption.
  </Card>
</CardGroup>

---

## Quick Example

Define your `@Table` model, initialize the database actor, and run reactive queries inside SwiftUI:

<CodeGroup>
```swift Model.swift
import BoutiqueDB
import StructuredQueries

@Table
struct Note {
    @Column(primaryKey: true) let id: UUID
    var title: String
    var body: String
    var createdAt: Date
}
```

```swift App.swift
import SwiftUI
import BoutiqueDB

@main
struct NotesApp: App {
    let db: BoutiqueDB
    
    init() {
        self.db = try! BoutiqueDB.open(
            url: BoutiqueDB.applicationSupportURL(),
            migrations: AppMigrations.plan
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(db: db)
        }
    }
}
```

```swift ContentView.swift
import SwiftUI
import BoutiqueDB
import StructuredQueries

struct ContentView: View {
    let db: BoutiqueDB
    
    @ObservationIgnored
    @LiveQuery var notes: [Note]
    
    init(db: BoutiqueDB) {
        self.db = db
        self._notes = LiveQuery(db) { Note.order { $0.title }.asSelect() }
    }
    
    var body: some View {
        List(notes, id: \.id) { note in
            VStack(alignment: .leading) {
                Text(note.title).font(.headline)
                Text(note.body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
```
</CodeGroup>

---

## Key Capabilities

| Feature | Status | Description |
| :--- | :---: | :--- |
| **Local CRUD** | <Check /> Ready | Type-safe model queries via `StructuredQueries` |
| **`LiveQuery` & `LiveQueryOne`** | <Check /> Ready | CDC-backed observation (< 250ms refresh latency) |
| **Concurrent Writes** | <Check /> Ready | Transaction busy-retry or MVCC `BEGIN CONCURRENT` |
| **CloudKit Sync** | <Check /> Beta | Private database sync via `CKSyncEngine` |
| **Migrations** | <Check /> Ready | Append-only named migrations with transactional rollbacks |
| **Full-Text Search (Tantivy)** | <Tip /> Opt-in | Fast BM25 full-text indexing via `index_method` |
| **Vector Search** | <Tip /> Opt-in | Dense and sparse vector indexing (`Vector32`) |
| **At-Rest Encryption** | <Tip /> Opt-in | `aegis256` or `aes256gcm` linked to Keychain |

---

## Explore the Documentation

<CardGroup cols={3}>
  <Card title="Quick Start" icon="rocket" href="/getting-started/quick-start">
    Set up BoutiqueDB in your Xcode project in under 5 minutes.
  </Card>
  <Card title="SwiftUI Integration" icon="mobile" href="/swiftui-integration">
    Learn how to build responsive, reactive views with `@LiveQuery`.
  </Card>
  <Card title="Turso Features" icon="sparkles" href="/turso-features-in-apple-apps">
    Unlock FTS, Vector embeddings, and MVCC concurrency.
  </Card>
</CardGroup>
