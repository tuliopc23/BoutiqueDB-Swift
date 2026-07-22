# BoutiqueDB Architecture

<p align="center">
  <img src="../Assets/BoutiqueDB.png" alt="BoutiqueDB" width="96" height="96" />
</p>

## Layers

```
SwiftUI / @Observable models
        │
        ▼
BoutiqueDB (@MainActor)          ← open + migrate + LiveQuery host
   ├── DatabaseActor             ← serialized I/O (reads/writes)
   ├── concurrent DatabaseActor  ← optional MVCC writer (CDC ⊥ MVCC)
   ├── TursoStore                ← AsyncStream / generation invalidation
   └── SyncAdapter               ← CloudKit (default) or future adapters
        │
        ▼
TursoKit → CTursoSQLite3 → libturso_sqlite3 (bindings/c)
```

## Concurrency rules (BD-014 / BD-005)

| Rule | Detail |
|---|---|
| UI container | `BoutiqueDB` is `@MainActor` — safe for SwiftUI |
| SQLite I/O | Always hop to `DatabaseActor` via `read` / `write` / `writeConcurrent` |
| CDC vs MVCC | Never enable both on one **primary** handle for same-handle MVCC+CDC init. Dual-handle `concurrentWrites` tries MVCC+CDC on the writer; if the engine rejects that, **falls back to busy-retry IMMEDIATE on the primary CDC connection** so `turso_cdc` is never silent |
| LiveQuery | Subscribes to `store.subscribe()`; local writes call `invalidate()` immediately. CDC poll is cooperative (~50 ms idle), not a push stream |
| Sync | Attach `BoutiqueDBSyncEngine.attach(to:)` so `onLocalCommit` auto-drains; manual `drainCDC` remains available |
| Connection escape | Prefer public APIs; `unsafeConnection` only for sync attachment / advanced use |

**Do not** call MainActor-isolated `BoutiqueDB` methods from inside a `DatabaseActor` body (deadlock risk).

## Feature map

| Concern | Doc / type |
|---|---|
| Migrations | [Migrations.md](Migrations.md), `BoutiqueMigrationPlan` |
| Observation | `LiveQuery`, `TursoStore` |
| Turso FTS / vector | `@FTSIndex`, `@VectorIndex`, `vectorDistance*`, `.match` |
| CloudKit | [CloudKit-QA-Checklist.md](CloudKit-QA-Checklist.md), `CloudKitSyncAdapter` |
| Capabilities | `TursoCapabilities.probe` |
| Benchmarks | [Sync-Benchmarks.md](Sync-Benchmarks.md) |

## Module products

| Product | Responsibility |
|---|---|
| `BoutiqueDB` | High-level API, macros client, migrations, dependencies key |
| `TursoKit` | Connections, statements, values |
| `StructuredQueriesTurso` | StructuredQueries driver + Turso DSL |
| `TursoCKSync` | CDC ↔ CKSyncEngine |
| `TursoObservation` | Change streams |
| `BoutiqueDBMacros` | Compiler plugin |

## Packaging note

Local SPM builds may link `libturso_sqlite3` via `Vendor/turso`. SPI-oriented binary packaging is tracked under refinement **R2**.
