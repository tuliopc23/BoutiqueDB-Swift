---
name: boutiquedb-architecture
description: |
  Explains the BoutiqueDB stack, module responsibilities, concurrency model, and engine surface.
  Use when the user asks about "BoutiqueDB architecture", "stack", "modules", "DatabaseActor",
  "LiveQuery internals", "TursoKit", or "CTursoSDK".
---

# BoutiqueDB architecture

Explain how the Swift package is layered, which module owns what, and how concurrency and observation work.

## Trigger phrases

- "BoutiqueDB architecture"
- "BoutiqueDB stack"
- "DatabaseActor"
- "LiveQuery how does it work"
- "TursoKit vs BoutiqueDB"
- "CTursoSDK"

## Workflow

1. **Show the stack diagram**:
   ```text
   SwiftUI / @Observable models
           │
           ▼
   BoutiqueDB (@MainActor)
      ├── DatabaseActor
      ├── concurrent DatabaseActor
      ├── TursoStore
      └── SyncAdapter
           │
           ▼
   TursoKit → CTursoSDK → libturso_sdk_kit
   ```
2. **Explain each module**:
   - `BoutiqueDB` — high-level container, migrations, LiveQuery host.
   - `TursoKit` — engine connection, statements, values.
   - `StructuredQueriesTurso` — query DSL and Turso extensions.
   - `TursoCKSync` — CDC ↔ CloudKit.
   - `TursoObservation` — change streams.
   - `BoutiqueDBMacros` — peer macros for tables and indexes.
   - `CTursoSDK` — C module wrapping `TursoSDK.xcframework`.
3. **State concurrency rules**:
   - `BoutiqueDB` is `@MainActor`.
   - Engine I/O runs on `DatabaseActor`.
   - Never call `BoutiqueDB` methods from inside a `DatabaseActor` closure.
   - `LiveQuery` refreshes via `AsyncStream` events from `TursoStore`.
4. **Explain `sdk-kit` vs `sqlite3` ABI**: `sdk-kit` (`turso.h`) is the primary surface for experimental features and `async_io`; `sqlite3` is legacy.
5. **Reference docs**:
   - `docs/stack.md`
   - `docs/advanced/boutiquedb-architecture.md`
   - `docs/guides/concurrency.md`
   - `docs/guides/live-queries.md`
