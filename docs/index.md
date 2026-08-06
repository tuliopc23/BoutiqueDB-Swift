---
title: "BoutiqueDB for Swift"
sidebarTitle: "Overview"
description: "Local-first persistence for iOS and macOS built on the Turso database engine with CloudKit sync, CDC live queries, and modern Swift concurrency."
mode: "custom"
hidden: true
---

<div className="hero-container not-prose">
  <img src="/icon.png" alt="BoutiqueDB" className="hero-icon" />
  <h1 className="hero-title">BoutiqueDB for Swift</h1>
  <p className="hero-subtitle">
    Local-first Swift persistence on the Turso engine. SQLiteData-style DX, CDC <code className="hero-code">LiveQuery</code>, CloudKit sync, and official Turso features — all inside your app sandbox.
  </p>
  <div className="hero-ctas">
    <a href="/getting-started/quick-start" className="hero-primary">Quick Start</a>
    <a href="/core-concepts" className="hero-secondary">Core Concepts</a>
  </div>
</div>

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

<h2 className="section-heading">Get started in three steps</h2>

<Steps>
  <Step title="Add BoutiqueDB" icon="plus">
    Add `https://github.com/tuliopc23/BoutiqueDB-Swift` to your Xcode project, Swift Package Manager, or `Package.swift`.
  </Step>

  <Step title="Define a model" icon="table">
    Annotate a Swift struct with `@Table` and `@Column`, then add it to a migration.
  </Step>

  <Step title="Run a LiveQuery" icon="bolt">
    Use `@LiveQuery` in a SwiftUI view to get reactive, CDC-backed updates without manual `onChange`.
  </Step>
</Steps>

---

<h2 className="section-heading">Quick Example</h2>

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

<h2 className="section-heading">Key Capabilities</h2>

| Feature | Status | Description |
| :--- | :---: | :--- |
| **Local CRUD** | <Badge color="green">Ready</Badge> | Type-safe model queries via `StructuredQueries` |
| **`LiveQuery` & `LiveQueryOne`** | <Badge color="green">Ready</Badge> | CDC-backed observation (< 250ms refresh latency) |
| **Concurrent Writes** | <Badge color="green">Ready</Badge> | Transaction busy-retry or MVCC `BEGIN CONCURRENT` |
| **CloudKit Sync** | <Badge color="yellow">Beta</Badge> | Private database sync via `CKSyncEngine` |
| **Migrations** | <Badge color="green">Ready</Badge> | Append-only named migrations with transactional rollbacks |
| **Full-Text Search (Tantivy)** | <Badge color="orange">Opt-in</Badge> | Fast BM25 full-text indexing via `index_method` |
| **Vector Search** | <Badge color="orange">Opt-in</Badge> | Dense and sparse vector indexing (`Vector32`) |
| **At-Rest Encryption** | <Badge color="orange">Opt-in</Badge> | `aegis256` or `aes256gcm` linked to Keychain |

---

<h2 className="section-heading">Explore the documentation</h2>

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
