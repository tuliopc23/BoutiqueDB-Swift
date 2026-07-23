---
title: "Full-Text Search & Vector Search"
sidebarTitle: "FTS & Vector Search"
description: "Implement BM25 full-text search and AI vector similarity search using Turso engine capabilities."
---

BoutiqueDB exposes Turso's native search extensions directly to Swift developers, enabling local full-text search and AI vector indexing.

---

## Full-Text Search (Tantivy BM25)

Turso incorporates **Tantivy**, a Rust full-text engine that delivers high-performance BM25 ranking and stemming.

### Creating an FTS Index

```swift FTSIndex.swift
// Open database with index_method feature flag enabled
let options = TursoOpenOptions(experimentalFeatures: [.indexMethod])
let db = try await BoutiqueDB.open(url: storeURL, options: options)

// Create Tantivy BM25 Index on article content
try await db.execute("""
    CREATE INDEX idx_articles_fts ON article (title, content)
    USING tantivy (tokenizer = 'en_stem')
""")
```

### Searching Text Content

```swift FTSQuery.swift
let queryText = "swiftui OR concurrency"

let searchResults = try await db.read { conn in
    try Article.where { #sql("title MATCH \(queryText)") }
        .fetchAll(conn.connection)
}
```

---

## Vector Search (Embeddings & Semantic Search)

BoutiqueDB natively supports 32-bit floating point vectors via the `Vector32` type.

### Storing Vectors in `@Table` Models

```swift DocumentVector.swift
import BoutiqueDB
import StructuredQueries

@Table
struct DocumentVector: Sendable {
    @Column(primaryKey: true) let id: UUID
    var title: String
    var embedding: Vector32 // Array wrapper for [Float32]
}
```

### Creating Vector Indexes & Distance Queries

```swift VectorSearch.swift
// Create HNSW Vector Index with Cosine Distance
try await db.execute("""
    CREATE INDEX idx_doc_vectors ON document_vector (embedding)
    USING vector (metric = 'cosine')
""")

// Query nearest neighbors to a prompt embedding
let promptVector: Vector32 = Vector32([0.05, -0.22, 0.78, 0.41])

let matches = try await db.read { conn in
    try conn.query("""
        SELECT title, vector_distance_cosine(embedding, ?) AS distance
        FROM document_vector
        ORDER BY distance ASC
        LIMIT 5
    """, [promptVector])
}
```

<Tip>
**On-Device AI Integration**: Combine `Vector32` with Apple's `NaturalLanguage` framework or CoreML models to execute vector similarity search on-device!
</Tip>
