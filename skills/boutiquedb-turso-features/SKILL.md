---
name: boutiquedb-turso-features
description: |
  Explains how to use Turso-only features in Apple apps: FTS, vector search, materialized views,
  generated columns, STRICT/WITHOUT ROWID, async I/O, MVCC, encryption, and multi-process WAL.
  Use when the user asks about "BoutiqueDB FTS", "BoutiqueDB vector search", "BoutiqueDB materialized views",
  "BoutiqueDB encryption", "BoutiqueDB multi-process", "Turso features BoutiqueDB", or "BoutiqueDB MVCC".
---

# BoutiqueDB Turso features in Apple apps

Help the user enable and use Turso-only features in iOS and macOS apps, with correct capability gating, examples, and warnings.

## Trigger phrases

- "BoutiqueDB FTS"
- "BoutiqueDB vector search"
- "BoutiqueDB materialized views"
- "BoutiqueDB encryption"
- "BoutiqueDB multi-process"
- "Turso features BoutiqueDB"
- "BoutiqueDB MVCC"
- "BoutiqueDB asyncIO"

## Workflow

1. **Enable features**: default `.tursoEnhanced` covers `views`, `index_method`, `generated_columns`, `vacuum`, `without_rowid`. Add `encryption`, `multiprocess_wal`, or `asyncIO` separately.
2. **Probe capabilities**:
   ```swift
   guard db.capabilities.ftsIndex else { /* fallback */ }
   guard db.capabilities.vectorIndex else { /* fallback */ }
   guard db.capabilities.materializedViews else { /* fallback */ }
   ```
3. **Feature examples**:
   - **FTS**:
     ```swift
     @BoutiqueTable
     @FTSIndex("title", "body")
     struct Article { ... }
     // query
     Article.where { $0.title.match("swift") }
            .order { $0.title.score("swift").desc() }
     ```
   - **Vector**:
     ```swift
     @BoutiqueTable
     @VectorIndex("embedding", metric: .cosine)
     struct Document { var embedding: Vector32 ... }
     // query
     let q = Vector32([...])
     Document.where { vectorDistanceCos($0.embedding, q) < 0.2 }
             .order { vectorDistanceCos($0.embedding, q) }
     ```
   - **Materialized views**:
     ```swift
     @MaterializedView(name: "tag_counts", as: "SELECT tag, COUNT(*) FROM notes GROUP BY tag")
     struct TagCount { ... }
     ```
   - **Generated columns / STRICT / WITHOUT ROWID**:
     ```swift
     @BoutiqueTable(strict: true, withoutRowid: true)
     struct Setting { ... }
     ```
   - **Encryption**:
     ```swift
     let key = try loadKeyFromKeychain() // 32 bytes
     let db = try BoutiqueDB(url: url, encryption: .aegis256(key: key))
     ```
   - **Multi-process WAL**:
     ```swift
     let db = try BoutiqueDB(url: groupURL, multiProcess: true)
     ```
   - **Async I/O**:
     ```swift
     let db = try BoutiqueDB(url: url, openOptions: .tursoEnhancedAsync)
     ```
   - **MVCC / concurrent writes**:
     ```swift
     let db = try BoutiqueDB(url: url, enableCDC: false, concurrentWrites: true)
     try await db.writeConcurrent { conn in ... }
     ```
4. **Warnings**:
   - CDC and MVCC are mutually exclusive; with CDC enabled `writeConcurrent` uses busy-retry `BEGIN IMMEDIATE`.
   - Experimental features may panic or return incorrect results; test thoroughly.
   - Store encryption keys in Keychain; never commit keys.
5. **Reference docs**:
   - `docs/turso-features-in-apple-apps.md`
   - `docs/guides/fts-and-vector.md`
   - `docs/advanced/experimental-features.md`
   - `docs/getting-started/open-options.md`
   - `docs/performance-tuning.md`
