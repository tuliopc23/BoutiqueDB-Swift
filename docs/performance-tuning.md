---
title: "Performance Tuning"
sidebarTitle: "Performance Tuning"
description: "Optimize database throughput, query latency, index usage, and memory overhead in iOS and macOS apps."
---

BoutiqueDB provides low-latency database operations powered by the Rust Turso engine. Follow these tuning techniques to maximize performance in high-throughput applications.

---

## Indexing & Query Latency

Ensure columns used in `WHERE`, `ORDER BY`, or `JOIN` clauses have supporting indexes.

```swift Indexes.swift
try conn.execute("""
    CREATE INDEX IF NOT EXISTS idx_task_completed_date 
    ON task_item (isCompleted, dueDate DESC)
""")
```

<Tip>
**Index Verification**: Run `EXPLAIN QUERY PLAN` on complex queries during development to verify index usage and eliminate full-table scans.
</Tip>

---

## Write Performance & Busy Retries

When multiple background tasks perform concurrent database writes, configure `TursoOpenOptions` to optimize write queueing:

```swift
let options = TursoOpenOptions(
    busyTimeout: .seconds(5) // Wait up to 5s during write lock contention
)

let db = try await BoutiqueDB.open(url: storeURL, options: options)
```

---

## Multi-Process WAL Optimization

For apps utilizing App Extensions (e.g. Share Extensions, WidgetKit, or Background Tasks), enable Multi-Process WAL mode:

```swift MultiProcess.swift
let options = TursoOpenOptions(
    multiProcessWAL: true
)
```

<Note>
**App Group Location**: Multi-Process WAL databases must reside within a shared App Group container URL so both the main app and extensions can access the shared memory `.shm` and `.wal` files.
</Note>
