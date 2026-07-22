---
name: boutiquedb-architecture
description: |
  Explains the BoutiqueDB stack, module responsibilities, concurrency model, LiveQuery, and engine surface.
  Use when the user asks about "BoutiqueDB architecture", "stack", "modules", "DatabaseActor",
  "LiveQuery internals", "TursoKit", "CTursoSDK", or "best practices".
---

# BoutiqueDB architecture

Explain how the Swift package is layered, which module owns what, how concurrency and observation work, and the key anti-patterns to avoid.

## Trigger phrases

- "BoutiqueDB architecture"
- "BoutiqueDB stack"
- "DatabaseActor"
- "LiveQuery how does it work"
- "TursoKit vs BoutiqueDB"
- "CTursoSDK"
- "BoutiqueDB best practices"

## Workflow

1. **Show the stack diagram**:
   ```text
   SwiftUI / @Observable models
           │
           ▼
   BoutiqueDB (@MainActor)
      ├── DatabaseActor (engine I/O)
      ├── TursoStore (change events)
      └── BoutiqueDBSyncEngine (CloudKit)
           │
           ▼
   TursoKit → CTursoSDK → libturso_sdk_kit
   ```
2. **Explain each module**:
   - `BoutiqueDB` — high-level `@MainActor` container, migrations, LiveQuery host.
   - `TursoKit` — engine connection, statements, values, CDC.
   - `StructuredQueriesTurso` — query DSL and Turso extensions (`match`, `vectorDistanceCos`, etc.).
   - `TursoCKSync` — CDC ↔ CloudKit.
   - `TursoObservation` — `TursoStore` change streams.
   - `BoutiqueDBMacros` — peer macros for `@BoutiqueTable`, `@FTSIndex`, `@VectorIndex`, `@MaterializedView`.
   - `CTursoSDK` — C module wrapping `TursoSDK.xcframework`.
3. **State concurrency rules**:
   - `BoutiqueDB` is `@MainActor`.
   - Engine I/O runs on `DatabaseActor`.
   - Never call `BoutiqueDB` methods from inside a `read`/`write` closure.
   - `LiveQuery` refreshes via `AsyncStream` events from `TursoStore`.
   - CDC and MVCC are mutually exclusive; `BoutiqueDB` chooses the safe path automatically.
4. **Explain `sdk-kit` vs `sqlite3` ABI**: `sdk-kit` (`turso.h`) is the primary surface for experimental features and `async_io`; the older `sqlite3` binding is legacy.
5. **Best practices**: append-only migrations, capability probes for Turso features, unique temp DBs per test, no `AUTOINCREMENT` with CloudKit.
6. **Reference docs**:
   - `docs/stack.md`
   - `docs/core-concepts.md`
   - `docs/best-practices.md`
   - `docs/guides/concurrency.md`
   - `docs/guides/live-queries.md`
