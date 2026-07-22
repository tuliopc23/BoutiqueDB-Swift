# FTS and vector search

BoutiqueDB exposes Turso’s full-text search and vector search features through typed Swift APIs and macros.

## Full-text search

Declare a full-text index with `@FTSIndex`:

```swift
import BoutiqueDB

@FTSIndex
extension Note {
  static let titleSearch = FTS(title, body, tokenizer: .default)
}
```

This generates `CREATE INDEX notes_title_fts ON notes USING fts (title, body)`.

Query with the DSL:

```swift
let results = try await db.read { conn in
  try Note.where { $0.title.match("swift") }
    .order { $0.title.score("swift").desc() }
    .fetchAll(conn)
}
```

Available helpers:

- `.match(_:)`
- `.score(_:)`
- `.highlight(query:before:after:)`

Tokenizers: `default`, `raw`, `simple`, `whitespace`, `ngram`.

## Vector search

Use `Vector32` for dense vectors:

```swift
import BoutiqueDB
import StructuredQueries

@VectorIndex
extension Document {
  static let embeddingIndex = VectorIndex(embedding, metric: .cosine)
}

struct Document: Sendable {
  var embedding: Vector32
}
```

Query by distance:

```swift
let neighbors = try await db.read { conn in
  try Document.where { vectorDistanceCos($0.embedding, query) < 0.2 }
    .order { vectorDistanceCos($0.embedding, query) }
    .limit(10)
    .fetchAll(conn)
}
```

Supported metrics:

- `cosine`
- `l2`
- `dot`
- `jaccard`

## Enabling index methods

Custom index methods require the `index_method` experimental feature. The default `TursoOpenOptions.tursoEnhanced` preset enables it. If you open with `TursoOpenOptions()`, you must add `.indexMethod` to the experimental features set.

> **Warning:** FTS, vector, and materialized views are experimental upstream. Test thoroughly before using them for critical data.

## Sparse vectors

For sparse vector indexes, use `Vector32Sparse` and the corresponding sparse vector functions.
