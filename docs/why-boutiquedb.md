# Why BoutiqueDB?

BoutiqueDB exists because the most common Swift persistence story — a raw SQLite wrapper or an ORM with hidden complexity — forces a trade-off between control and ergonomics. BoutiqueDB aims to keep the file format simple, the API Swift-native, and the sync story optional.

## Compared to raw SQLite or GRDB

BoutiqueDB is not trying to be a thin SQLite wrapper. It is a higher-level persistence layer with:

- **Type-safe model definitions** via `swift-structured-queries` `@Table` and `@Column`.
- **Live, observable queries** backed by CDC instead of polling.
- **CloudKit sync** as a first-class module rather than a bolt-on.
- **Optional Turso engine features** such as FTS, vector indexes, and materialized views, exposed through typed Swift APIs and macros.

If you need full SQL control, the underlying `TursoKit` and `StructuredQueriesTurso` still give you prepared statements and raw SQL escape hatches.

## Compared to Core Data or SwiftData

Core Data and SwiftData are deeply integrated with Apple platforms and object graphs. BoutiqueDB is a relational, file-first alternative for apps that:

- Want a predictable, query-driven model layer.
- Need to inspect or migrate the database schema with version-controlled SQL migrations.
- Prefer a local-first architecture where sync is explicit and replaceable.

## Compared to a server-backed database

BoutiqueDB keeps data in the app sandbox. There is no network round-trip for reads or writes. CloudKit sync is asynchronous and opportunistic; the app continues to work offline. If you later want Turso Cloud sync, the `SyncAdapter` protocol is designed so the local engine and schema remain the same.

## When BoutiqueDB is the right fit

- iOS or macOS apps that use SwiftUI and `Observation`.
- Apps that want local-first data with CloudKit private-database sync.
- Projects where query performance, FTS, vector search, or concurrent writes matter.
- Teams that prefer explicit migrations and a source-controlled schema.

## When to choose something else

- You need a full object graph with object identity and faulting (Core Data may fit better).
- You require real-time multi-device collaboration (you will need a server backend).
- Your data model is document-oriented and you do not need SQL queries.
