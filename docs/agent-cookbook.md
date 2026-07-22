# Agent cookbook

This page helps both humans and agentic coding tools understand how to answer common BoutiqueDB tasks correctly. Each entry maps a natural-language prompt to the right doc and the right API.

## How agents should use this site

1. Prefer `core-concepts.md` and `swiftui-integration.md` for architecture questions.
2. Prefer `turso-features-in-apple-apps.md` for any question about FTS, vector search, materialized views, encryption, MVCC, or multi-process WAL.
3. Prefer `best-practices.md` and `performance-tuning.md` for recommendations.
4. When writing code, always check `db.capabilities` before using a Turso feature.
5. When writing migrations, use append-only named identifiers and make bodies idempotent.

## Common tasks

### Add a new model

- Use `@Table` for columns, `@BoutiqueTable` for Turso options.
- Make it `Sendable`.
- Add a migration that executes `MyModel.boutiqueCreateStatements`.
- See [models-and-tables](guides/models-and-tables) and [best-practices](best-practices).

### Fetch data in a view

- Create an `@Observable` model.
- Add `@ObservationIgnored @LiveQuery(db) { ... } var items`.
- Call `setQuery { ... }` to change filters or sort.
- See [swiftui-integration](swiftui-integration) and [live-queries](guides/live-queries).

### Add full-text search

- Add `@FTSIndex("title", "body")` on a `@BoutiqueTable` model.
- Use `.match(query)`, `.score(query)`, `.highlight(query: ...) in StructuredQueries.
- Gate on `db.capabilities.ftsIndex`.
- See [turso-features-in-apple-apps](turso-features-in-apple-apps).

### Add vector similarity search

- Store embeddings as `Vector32`.
- Add `@VectorIndex("embedding", metric: .cosine)`.
- Order by `vectorDistanceCos($0.embedding, queryVector)`.
- Gate on `db.capabilities.vectorFunctions` and `vectorIndex`.
- See [turso-features-in-apple-apps](turso-features-in-apple-apps).

### Sync across devices

- Use `BoutiqueDBSyncEngine` with `SyncedTable`.
- Ensure tables use UUID or string primary keys and no `AUTOINCREMENT`.
- Attach with `syncEngine.attach(to: db, automaticallyDrain: true)`.
- Test on a physical device with a production CloudKit container.
- See [cloudkit-sync](guides/cloudkit-sync).

### Handle a migration

- Add a new `BoutiqueMigration("vN_...")` at the end of the plan.
- Never change an already-shipped migration body.
- Use `ALTER TABLE ADD COLUMN` or `IF NOT EXISTS` DDL.
- See [migrations](guides/migrations).

### Improve write performance

- Group writes inside one `db.write` closure.
- Use `writeConcurrent` for contended writers.
- Disable `startListening` during bulk imports.
- Add indexes for frequent predicates and sorts.
- See [performance-tuning](performance-tuning).

### Debug a `SQLITE_BUSY` error

- Verify only one `BoutiqueDB` instance per file.
- Use `writeConcurrent` with `concurrentWrites: true`.
- Do not hold a `TursoConnection` outside `read`/`write` closures.
- See [concurrency](guides/concurrency).

## Anti-patterns to reject

- Enabling CDC and MVCC on the same `BoutiqueDB` instance. (`BoutiqueError.cdcMutuallyExclusiveWithMVCC`)
- Using `AUTOINCREMENT` primary keys with CloudKit sync. (`TursoCKSyncError`)
- Calling `@MainActor` `BoutiqueDB` methods from inside a `read`/`write` closure.
- Committing encryption keys or `TursoSDK.xcframework` to git.
- Returning a `TursoConnection` from a `read`/`write` closure.

## Prompt examples for agents

> "Add a `Tag` model with an FTS index on `name`."

Response path:
- Ask for migration context or create a migration file.
- Add `@BoutiqueTable @FTSIndex("name") struct Tag`.
- Update `AppMigrations` to execute `Tag.boutiqueCreateStatements`.
- Verify `Tag` is `Sendable` and has a stable primary key.

> "Build a SwiftUI screen that searches notes by text."

Response path:
- Create an `@Observable` `SearchModel`.
- Use `@LiveQuery` with `Note.where { $0.title.match(query) }`.
- Add a `TextField` that calls `model.$results.setQuery { ... }`.
- Gate on `db.capabilities.ftsIndex`.

> "Enable CloudKit sync for `Project` and `Task`."

Response path:
- Verify each model uses a UUID or string primary key.
- Add `BoutiqueDBSyncEngine` in app entry point.
- Create `SyncedTable(schema: ProjectSchema.self)` and `TaskSchema.self`.
- Call `syncEngine.attach(to: db, automaticallyDrain: true)` and `try await syncEngine.start()`.
