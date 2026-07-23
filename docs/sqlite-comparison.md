---
title: "SQLite & Framework Comparison"
sidebarTitle: "SQLite Comparison"
description: "Detailed comparison between BoutiqueDB, SQLite, GRDB, CoreData, and SwiftData for Apple app developers."
---

Choosing the right persistence framework for your iOS or macOS application impact stability, concurrency model, and long-term codebase ergonomics.

This guide compares **BoutiqueDB** against existing database choices in the Apple ecosystem.

---

## Technical Comparison

<AccordionGroup>
  <Accordion title="BoutiqueDB vs GRDB" icon="scale-balanced">
    **GRDB** is an exceptional, mature SQLite toolkit for Swift. 

    **Key Differences**:
    - **Engine Architecture**: GRDB compiles against system `libsqlite3.dylib` or custom SQLCipher builds. BoutiqueDB runs on the Rust **Turso engine** (`sdk-kit`).
    - **CDC Observation**: GRDB relies on SQLite `update_hook` transaction monitoring. BoutiqueDB uses native Change Data Capture (`turso_cdc`), allowing CDC observation across multi-process WAL setups and background sync tasks.
    - **Turso Features**: BoutiqueDB natively supports Tantivy BM25 FTS, vector search (`Vector32`), and IVM materialized views without extra C compilation steps.
  </Accordion>

  <Accordion title="BoutiqueDB vs SwiftData & CoreData" icon="apple">
    **SwiftData** and **CoreData** are Apple's official object-graph persistence frameworks.

    **Key Differences**:
    - **Object Graph vs Value Types**: CoreData/SwiftData manage complex object graphs with faulting and managed object contexts. BoutiqueDB operates purely on **immutable Swift structs** (`Sendable`).
    - **Concurrency Model**: CoreData requires `performBackgroundTask` or `ModelActor`. BoutiqueDB uses Swift `@MainActor` for UI components and background `DatabaseActor` execution.
    - **CloudKit Control**: SwiftData handles CloudKit sync automatically but offers limited debugging control when conflicts arise. BoutiqueDB exposes `CKSyncEngine` status, record mapping, and conflict hooks directly.
  </Accordion>

  <Accordion title="BoutiqueDB vs Raw SQLite3" icon="database">
    **Raw `sqlite3` C API** offers total control but requires manual memory management, raw SQL string queries, and custom binding handlers.

    **Key Differences**:
    - **Ergonomics**: BoutiqueDB uses `StructuredQueries` macro models (`@Table`) to generate type-safe SQL queries at compile time.
    - **Safety**: Raw SQLite C functions easily introduce thread-safety violations and SQL injection risks if not sanitized. BoutiqueDB provides type-safe parameter binding.
  </Accordion>
</AccordionGroup>

---

## Detailed Feature Matrix

| Feature | BoutiqueDB | GRDB | SwiftData | Raw SQLite3 |
| :--- | :---: | :---: | :---: | :---: |
| **Model Definition** | Swift `@Table` Structs | Record Protocols / Structs | `@Model` Classes | Raw C Structs / SQL |
| **Query Ergonomics** | Type-Safe DSL | Type-Safe Query Interface | `#Predicate` Macros | Raw SQL Strings |
| **Change Observation** | `@LiveQuery` (CDC) | `ValueObservation` | `@Query` | Manual Triggers |
| **Thread Isolation** | `DatabaseActor` | `DatabaseQueue` / `DatabasePool` | `ModelActor` | Manual Mutex / WAL |
| **Encryption** | AEGIS / AES256 | SQLCipher | Data Protection | Custom / SQLCipher |
| **CloudKit Sync** | `CKSyncEngine` Native | Manual Setup | Built-in | Custom |

<Tip>
**Migrating from GRDB or SQLite**: Because BoutiqueDB databases use standard SQLite-compatible file formats on disk, existing SQLite `.sqlite` files can be opened directly by `BoutiqueDB` without needing data export/import routines!
</Tip>
