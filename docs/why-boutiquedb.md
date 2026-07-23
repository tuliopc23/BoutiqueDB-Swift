---
title: "Why BoutiqueDB?"
sidebarTitle: "Why BoutiqueDB?"
description: "Discover why BoutiqueDB is built specifically for Apple platforms, combining local-first persistence with Turso engine capabilities."
---

Building modern iOS and macOS applications requires a persistence layer that is **fast, reliable, thread-safe, and offline-ready**. Standard solutions often force developer tradeoffs between complex ORM abstractions and low-level SQL C APIs.

BoutiqueDB combines the local-first ergonomics of SQLite with modern Swift concurrency, Change Data Capture (CDC) observation, and Apple CloudKit sync.

---

## Key Advantages

<CardGroup cols={2}>
  <Card title="Offline & Local-First" icon="wifi-slash">
    Your database lives locally on the user's device. Apps launch instantly and operate seamlessly without network connectivity.
  </Card>
  <Card title="Swift Concurrency Safe" icon="swift">
    Built from the ground up with `@MainActor` UI safety and isolated background `DatabaseActor` execution.
  </Card>
  <Card title="CDC Reactive Updates" icon="arrows-rotate">
    UI views update automatically (< 250ms latency) via native Change Data Capture without heavy polling or manual notifications.
  </Card>
  <Card title="Zero Server Overhead" icon="cloud">
    Sync data seamlessly across user Apple devices using private CloudKit containers without managing servers or API endpoints.
  </Card>
</CardGroup>

---

## Comparison Matrix

| Feature | BoutiqueDB | SwiftData / CoreData | GRDB | Raw SQLite3 |
| :--- | :---: | :---: | :---: | :---: |
| **Local SQLite File** | <Check /> | <Check /> | <Check /> | <Check /> |
| **Swift Concurrency (`async/await`)** | <Check /> | <Check /> | <Check /> | <Warning /> Manual |
| **Type-Safe Queries (`@Table`)** | <Check /> | <Check /> | <Check /> | <Warning /> Strings |
| **CDC Live Observation** | <Check /> | <Warning /> KVO / NSFRC | <Check /> | <Warning /> Manual |
| **CloudKit Private Sync** | <Check /> | <Check /> | <Warning /> Extra setup | <Warning /> Custom |
| **Full-Text Search (Tantivy BM25)** | <Tip /> Native | <Warning /> Basic FTS | <Warning /> FTS5 | <Warning /> FTS5 |
| **Vector Search (AI Embeddings)** | <Tip /> Native | <Warning /> No | <Warning /> Extension | <Warning /> Extension |
| **Hardware Encryption (AEGIS)** | <Tip /> Built-in | <Warning /> Data Protection | <Warning /> SQLCipher | <Warning /> Custom |

---

## Architectural Philosophy

1. **Local-First Authority**: The database file inside your app sandbox is the single source of truth. Network synchronization is asynchronous and non-blocking.
2. **Type Safety Without Magic**: Models use compile-time macros (`@Table`) so queries remain standard Swift code.
3. **Explicit Over Implicit**: Schema migrations and experimental engine flags (`TursoOpenOptions`) are explicit and version-controlled.
