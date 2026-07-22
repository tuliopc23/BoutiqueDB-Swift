# FTS and vector search

BoutiqueDB exposes Turso’s full-text search and vector search features through typed Swift APIs and macros.

## Full-text search

Declare a full-text index with `@FTSIndex` on a `@BoutiqueTable` model:

```swift
import BoutiqueDB
import StructuredQueries

@BoutiqueTable
@FTSIndex("title", "body", tokenizer: .default)
struct Article: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
}
```

This emits:

```sql
CREATE INDEX articles_title_body_fts ON articles USING fts(title, body) WITH (tokenizer = 'default')
```

Query with the DSL:

```swift
let results = try await db.read { conn in
  try Article.where { $0.title.match("swift") }
    .order { $0.title.score("swift").desc() }
    .limit(20)
    .fetchAll(conn.connection)
}
```

Available helpers on `String` columns:

- `.match(_:)` — Tantivy boolean query.
- `.score(_:)` — BM25 relevance score.
- `.highlight(query:before:after:)` — highlighted snippets.

Tokenizers: `default`, `raw`, `simple`, `whitespace`, `ngram`.

## Vector search

Use `Vector32` for dense vectors:

```swift
@BoutiqueTable
@VectorIndex("embedding", metric: .cosine)
struct Document: Sendable {
  @Column(primaryKey: true) let id: UUID
  var embedding: Vector32
}
```

Query by distance:

```swift
let query = Vector32([0.1, 0.2, 0.3])

let neighbors = try await db.read { conn in
  try Document.where { vectorDistanceCos($0.embedding, query) < 0.2 }
    .order { vectorDistanceCos($0.embedding, query) }
    .limit(10)
    .fetchAll(conn.connection)
}
```

Supported metrics: `cosine`, `l2`, `dot`, `jaccard`.

## Sparse vectors

For sparse embeddings use `Vector32Sparse`:

```swift
let sparse = Vector32Sparse([0: 1.0, 5: 0.5])
try await db.execute(
  "INSERT INTO docs (id, embedding) VALUES (?, vector32_sparse(?))",
  [.text(id.uuidString), .text(sparse.jsonLiteral)]
)
```

## Enabling index methods

Custom index methods require the `index_method` experimental feature. The default `TursoOpenOptions.tursoEnhanced` preset enables it. If you open with `TursoOpenOptions()`, add `.indexMethod` to the experimental features set.

Always gate runtime usage on `db.capabilities.ftsIndex` and `db.capabilities.vectorIndex`.

> **Warning:** FTS, vector, and materialized views are experimental upstream. Test thoroughly before using them for critical data.

For a complete feature guide, see [Turso features in Apple apps](../turso-features-in-apple-apps).
