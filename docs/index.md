---
title: "BoutiqueDB for Swift"
sidebarTitle: "Overview"
description: "Local-first persistence for iOS and macOS built on the Turso database engine with CloudKit sync, CDC live queries, and modern Swift concurrency."
mode: "custom"
---

<div className="bd-hero">
  <img src="/icon.png" className="bd-logo" alt="BoutiqueDB" />

  <p className="bd-eyebrow">LOCAL-FIRST SWIFT PERSISTENCE</p>
  <h1>BoutiqueDB<br />for modern Apple apps.</h1>
  <p className="bd-lead">A native Swift database layer built around SQLite compatibility, StructuredQueries, reactive CDC observation, Swift concurrency, and optional CloudKit sync.</p>

  <div className="bd-actions">
    <a className="bd-primary" href="/getting-started/quick-start">Start building</a>
    <a className="bd-secondary" href="/core-concepts">Explore architecture</a>
  </div>
</div>

<CardGroup cols={3}>
    
</CardGroup>

## A database layer designed like a Swift framework

BoutiqueDB combines the reliability of SQLite with modern Swift ergonomics. Define models, write type-safe queries, observe changes, and build offline-first applications without fighting your persistence layer.

<CodeGroup>

```swift
@Table
struct Note {
    @Column(primaryKey: true) var id: UUID
    var title: String
}
```

```swift
@LiveQuery var notes: [Note]
```

</CodeGroup>

## Architecture

<CardGroup cols={2}>
     
</CardGroup>

## Documentation

<Steps>
</Steps>