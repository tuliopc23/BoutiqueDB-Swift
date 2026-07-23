---
title: "Turso Engine Features in Apple Apps"
sidebarTitle: "Turso Features"
description: "Leverage Turso-exclusive engine capabilities: Full-Text Search (Tantivy), Dense/Sparse Vector Search, IVM Materialized Views, and AEGIS Encryption."
---

BoutiqueDB is powered by the **Turso Rust database engine** (`sdk-kit`). This unlocks advanced database features directly inside your iOS and macOS applications without managing remote servers.

---

## 1. Full-Text Search (Tantivy BM25)

Turso replaces traditional SQLite FTS5 with **Tantivy**, a state-of-the-art Rust full-text search engine. 

### Enabling FTS Token & Indexing

Enable the `index_method` feature token when initializing BoutiqueDB:

```swift FTSSetup.swift
import BoutiqueDB

let options = TursoOpenOptions(
    experimentalFeatures: [.indexMethod]
)

let db = try await BoutiqueDB.open(
    url: BoutiqueDB.applicationSupportURL().appendingPathComponent("app.sqlite"),
    options: options
)

// Create Tantivy FTS index on title and body columns
try await db.execute("""
    CREATE INDEX idx_notes_fts ON note (title, body) 
    USING tantivy (tokenizer = 'en_stem')
""")
```

### Performing FTS Queries

```swift FTSQuery.swift
let searchResults = try await db.read { conn in
    try Note.where { #sql("title MATCH 'swift OR concurrency'") }
        .fetchAll(conn.connection)
}
```

---

## 2. Vector Search (AI & Embeddings)

Store, index, and query dense and sparse embeddings (e.g., from Apple's NaturalLanguage framework or OpenAI API) directly inside your local database.

### Vector Data Types

BoutiqueDB supports 32-bit floating point vectors via `Vector32`:

```swift VectorModel.swift
import BoutiqueDB

@Table
struct DocumentEmbedding {
    @Column(primaryKey: true) let id: UUID
    var documentId: UUID
    var embedding: Vector32 // [Float32] array wrapper
}
```

### Building Vector Indexes & KNN Distance Search

```swift VectorSearch.swift
// Create a vector index using HNSW or IVF
try await db.execute("""
    CREATE INDEX idx_embeddings ON document_embedding (embedding)
    USING vector (metric = 'cosine')
""")

// Find top 5 nearest neighbors to a query embedding
let queryVector: Vector32 = Vector32([0.12, -0.44, 0.89, 0.23])

let nearestDocs = try await db.read { conn in
    try conn.query("""
        SELECT documentId, vector_distance_cosine(embedding, ?) AS score
        FROM document_embedding
        ORDER BY score ASC
        LIMIT 5
    """, [queryVector])
}
```

---

## 3. Incremental View Maintenance (IVM Materialized Views)

Turso supports instant, auto-updating materialized views that automatically stay in sync with underlying tables as rows are inserted or mutated.

```swift MaterializedViews.swift
let options = TursoOpenOptions(
    experimentalFeatures: [.views]
)

let db = try await BoutiqueDB.open(url: storeURL, options: options)

// Create an incrementally maintained materialized view
try await db.execute("""
    CREATE MATERIALIZED VIEW mv_active_user_stats AS
    SELECT userId, COUNT(*) as totalTasks, SUM(isCompleted) as completedTasks
    FROM task_item
    GROUP BY userId
""")
```

---

## 4. Hardware-Accelerated At-Rest Encryption

Protect sensitive user data inside the iOS Keychain using Turso's zero-overhead AEGIS or AES encryption.

```swift KeyedDB.swift
import BoutiqueDB

let secretKeyData = KeychainManager.getOrCreateDatabaseKey()

let options = TursoOpenOptions(
    encryptionKey: secretKeyData, // 256-bit key
    cipher: .aegis256            // AEGIS-256 (ARMv8 hardware accelerated)
)

let db = try await BoutiqueDB.open(
    url: BoutiqueDB.applicationSupportURL().appendingPathComponent("secure.sqlite"),
    options: options
)
```

---

## 5. Concurrent Writes (`BEGIN CONCURRENT`)

Eliminate `SQLITE_BUSY` errors when writing across multiple background threads or background tasks.

```swift ConcurrentWrites.swift
try await db.writeConcurrent { conn in
    try TaskItem.insert {
        TaskItem(id: UUID(), title: "Background Sync Item", isCompleted: true, createdAt: Date())
    }.execute(conn.connection)
}
```

<Note>
**Opt-In Design**: Advanced Turso features are completely opt-in. Standard BoutiqueDB databases behave like lightweight, standard SQLite files unless specific `TursoOpenOptions` are toggled.
</Note>
