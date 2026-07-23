# BoutiqueDB — Turso-exclusive features and macro opportunities

This doc maps Turso-only features to the most ergonomic Swift API shape for BoutiqueDB. It separates *runtime/API* work from *macro/property-wrapper* work and flags what the `sdk-kit` (`turso.h`) C ABI exposes.

## Important caveat: the sdk-kit C ABI

The package uses the official `sdk-kit` C ABI (`turso.h` / `libturso_sdk_kit`). It exposes CDC (`PRAGMA capture_data_changes_conn`), `BEGIN CONCURRENT`, FTS, vector functions, materialized views, normal SQL, and per-database experimental features through `turso_database_config_t`.

Per-open flags are passed as a CSV string in `experimental_features`:

- `views`
- `custom_types`
- `encryption`
- `index_method`
- `generated_columns`
- `multiprocess_wal`
- `attach`
- `without_rowid`
- `vacuum`
- `mvcc_passive_checkpoint`

These flags are opt-in and gated by `TursoOpenOptions` / `TursoCapabilities`.

---

## 1. CDC (Change Data Capture) — DONE

What it is:

- `PRAGMA capture_data_changes_conn('full')` writes change records to `turso_cdc`.
- Used by the sync engine and by live observation.

Swift shape:

- Property wrappers `@LiveQuery` and `@LiveQueryOne` already consume CDC indirectly via `TursoStore.generation`.

Macro need:

- **None.** The wrappers are the right surface. Future work should replace the 100 ms poll with a true CDC `AsyncStream`.

---

## 2. MVCC / `BEGIN CONCURRENT`

What it is:

- `PRAGMA journal_mode = mvcc;` then `BEGIN CONCURRENT;` allows optimistic concurrent writers.
- Commit fails with `SQLITE_BUSY` on write-write conflict; app retries.

Swift shape:

- API methods on `BoutiqueDB`:
  - `try db.beginConcurrent()`
  - `try db.commitConcurrent()`
  - `try db.writeConcurrent { ... }` with automatic retry/backoff

Macro / property-wrapper need:

- **None.** This is an imperative transaction mode, not a declarative view. A `@Concurrent` property wrapper would not make sense.

Notes:

- CDC and MVCC are mutually exclusive; `BoutiqueDB` should guard against enabling both on the same connection.
- The `sdk-kit` C API supports this through SQL pragmas/statements, so no new Rust exports are needed.

---

## 3. Async writes

What it is:

- Turso's core is cooperatively async (`IOResult`), but the C API is synchronous.
- JS/Node SDK exposes `transactionAsync(async (tx) => ...)` so long-running writes do not block the event loop.

Swift shape:

- API methods:
  - `try await db.write { ... }`
  - `try await db.transaction { ... }`
- Internally these run the closure on a background queue/actor and `await` the result.

Macro / property-wrapper need:

- **Low.** A `@BackgroundWrite` property wrapper would be confusing (writes are side effects, not observable state). Just make the existing `write`/`transaction` methods `async`.

---

## 4. Full-Text Search (FTS)

What it is:

- `CREATE INDEX idx ON articles USING fts (title, body);`
- Query functions: `fts_match(col1, col2, 'query')`, `fts_score(col1, col2, 'query')`, `fts_highlight(col1, col2, before, after, 'query')`.
- Tokenizers (`default`, `raw`, `simple`, `whitespace`, `ngram`) and per-column weights via `WITH (...)`.

Swift shape options:

1. **Macro for declaring the index:**
   ```swift
   @FTSIndex
   extension Note {
     static let titleSearch = FTS(title, body, tokenizer: .default)
   }
   ```
   This would generate the `CREATE INDEX ... USING fts` statement and a typed `FTSConfig`.

2. **DSL / query helpers:**
   ```swift
   Note.where { $0.title.match("swift") }
   Note.where { $0.title.score("swift") > 0 }
   ```
   These are runtime query builders, not macros.

3. **Live property wrapper:**
   ```swift
   @LiveQuery(search: Note.titleSearch, "swift") var results: [Note]
   ```
   This is a possible future overload on `@LiveQuery`.

Macro need:

- **Medium.** A small `@FTSIndex` macro reduces boilerplate and keeps column/tokenizer config type-safe. The query functions themselves are better as DSL methods because `swift-structured-queries` can compose them.

C-binding notes:

- FTS works through normal SQL, so no new Rust exports are needed.
- Custom index methods (`CREATE INDEX ... USING fts/vector`) require the `index_method` token in `turso_database_config_t.experimental_features`; `TursoOpenOptions.tursoEnhanced` includes it by default.

---

## 5. Vector search

What it is:

- Vector functions: `vector32('[...]')`, `vector32_sparse('[...]')`, `vector_distance_cos/l2/dot/jaccard(v1, v2)`.
- Sparse vector indexes via `CREATE INDEX ... USING vector` (experimental, `--experimental-index-method`).

Swift shape options:

1. **Macro for index declaration:**
   ```swift
   @VectorIndex
   extension Document {
     static let embeddingIndex = VectorIndex(embedding, metric: .cosine)
   }
   ```

2. **Value types + DSL:**
   ```swift
   struct Document {
     var embedding: Vector32
   }

   Document.where { vectorDistanceCos($0.embedding, query) < 0.2 }
     .order { vectorDistanceCos($0.embedding, query) }
     .limit(10)
   ```

Macro need:

- **Medium.** A `@VectorIndex` macro for index DDL is useful, but most of the ergonomics come from a `Vector32` / `Vector32Sparse` type and `vectorDistance*` functions in the DSL.

C-binding limitation:

- Same as FTS: vector functions are exposed through SQL, but the sparse-vector *index method* needs `--experimental-index-method`, which is not toggled by `turso_enable_experimental()`.

---

## 6. Materialized views (IVM)

What it is:

- `CREATE MATERIALIZED VIEW customer_totals AS SELECT ... GROUP BY ...;`
- Auto-updated via Incremental View Maintenance when base tables change.

Swift shape options:

1. **Macro for defining the view + model:**
   ```swift
   @MaterializedView
   struct CustomerTotals: Table {
     var customerId: Int
     var orderCount: Int
     var totalSpent: Double

     static var source: some QueryExpression<...> {
       Order.select { ($0.customerId, count, sum(\.$0.amount)) }
         .group { $0.customerId }
     }
   }
   ```
   This would emit `CREATE MATERIALIZED VIEW "CustomerTotals" AS <source SQL>` and make the view queryable like a `@Table`.

2. **Runtime helper:**
   ```swift
   try db.createMaterializedView(
     "customer_totals",
     from: Order.select { ... }.group { ... }
   )
   ```

Macro need:

- **High for ergonomics, but tricky.** Materialized views have limited SQL support (no nested views, not all functions), so a macro that validates the Swift expression and emits the `CREATE` statement is valuable. However, the macro must avoid duplicating the full query DSL. A peer macro on a `@Table`-like struct is the natural choice.

C-binding limitation:

- Materialized views require `--experimental-views`, which is **not** enabled by `turso_enable_experimental()`. Like FTS/vector, this needs the Rust `Builder` option or a new C setter.

---

## 7. Generated columns, WITHOUT ROWID, STRICT tables

What they are:

- `GENERATED ALWAYS AS (expression) VIRTUAL` columns.
- `CREATE TABLE ... WITHOUT ROWID`.
- `CREATE TABLE ... STRICT`.

Swift shape:

- These are *table-definition* options. The cleanest path is to extend the existing `@Table`/`@Column` macro parameters:
  ```swift
  @Table(withoutRowid: true, strict: true)
  struct Note { ... }

  @Column(generated: .virtual, expression: "lower(title)")
  var lowercasedTitle: String
  ```

Macro need:

- **High.** But this belongs in `swift-structured-queries` (or a wrapper macro `@BoutiqueTable`) rather than a separate BoutiqueDB macro. `@Column(generated:)` already exists in `swift-structured-queries`; `WITHOUT ROWID` and `STRICT` do not.

C-binding limitation:

- `turso_enable_experimental()` turns on generated columns and WITHOUT ROWID. STRICT is a normal SQLite feature and should work without flags.

---

## 8. Encryption

What it is:

- `PRAGMA cipher = 'aegis256'; PRAGMA hexkey = '...';` for at-rest encryption.

Swift shape:

- `BoutiqueDB(url: ..., encryption: .aegis256(key: ...))` init.
- No macro; encryption is an open-time configuration.

C-binding limitation:

- Encryption requires `--experimental-encryption` in the Rust `Builder`; the C binding does not expose an open-with-encryption API. We would need to add a new C function or use the Rust `Builder` directly.

---

## 9. Multi-process WAL / ATTACH

What they are:

- Share one database file across OS processes (`--experimental-multiprocess-wal`).
- Attach additional databases (`--experimental-attach`).

Swift shape:

- `BoutiqueDB(url: ..., multiProcess: true)`
- `try db.attach(url: ..., alias: "replica")`

Macro need:

- **None.** These are open/connection configuration APIs.

---

## 10. Custom types / domains

What they are:

- `CREATE TYPE`, `CREATE DOMAIN` for STRICT tables.

Swift shape:

- Could be modeled as a `RawRepresentable` enum with a `QueryBindable` conformance.
- No obvious macro; a macro would add little over a simple `enum` conformance.

Macro need:

- **Low.**

---

## Summary: which features deserve macros/property wrappers?

| Feature | Priority | Swift surface | Macro? |
|---------|----------|---------------|--------|
| CDC / live queries | Done | `@LiveQuery`, `@LiveQueryOne` | Property wrapper — done |
| MVCC `BEGIN CONCURRENT` | High | `writeConcurrent()`, `beginConcurrent()` | No |
| Async writes | Medium | `async write` / `transaction` | No |
| FTS | High | `fts_match/score/highlight` DSL + `@FTSIndex` macro | **Macro useful** |
| Vector search | High | `Vector32` type + `vectorDistance*` DSL + `@VectorIndex` | **Macro useful** |
| Materialized views | Medium | `@MaterializedView` or `createMaterializedView()` | **Macro useful** |
| Generated cols / WITHOUT ROWID / STRICT | High | Extend `@Table`/`@Column` options | **Macro/parameter extension** |
| Encryption | Medium | `BoutiqueDB(...encryption:)` init | No |
| Multi-process / ATTACH | Low | Init / attach API | No |
| Custom types | Low | Conformance helpers | No |

## Recommendation (v2)

1. **Build `BoutiqueDBMacros` as a dedicated `.macro` target** in Phase 2. It provides `@BoutiqueTable`, `@FTSIndex`, `@VectorIndex`, and `@MaterializedView` and is the ergonomic backbone of the v2 framework.
2. **Implement `@FTSIndex` and `@VectorIndex` peer macros** and gate their DDL behind a runtime `TursoCapability` check, because the C build may or may not have `--experimental-index-method` enabled. See `BoutiqueDB-Issues.md` (BD-002).
3. **Pursue `WITHOUT ROWID` / `STRICT` / generated columns** through a `@BoutiqueTable` wrapper macro that extends `@Table`/`@Column`, rather than waiting for upstream changes.
4. **Keep MVCC and async writes purely API-level** because they are transaction/execution concerns, not declarative model concerns.
5. **Track open C-binding limitations** (encryption, multi-process WAL, experimental views) in `BoutiqueDB-Issues.md` (BD-001, BD-003, BD-004) and resolve each with a small C setter or a documented custom build flag before `v1.0.0`.
