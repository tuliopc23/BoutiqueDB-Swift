---
name: boutiquedb-open-options
description: |
  Explains TursoOpenOptions, experimental feature tokens, async I/O, encryption, multi-process WAL, and capability probes.
  Use when the user asks about "BoutiqueDB open options", "experimental features",
  "TursoOpenOptions", "asyncIO", "encryption", "multiProcess", "capability probe",
  "vector search", "FTS", or "materialized views".
---

# BoutiqueDB open options and Turso features

Explain how `TursoOpenOptions` maps to the official `sdk-kit` engine configuration, how to enable experimental features safely, and how to use Turso-only features in Apple apps.

## Trigger phrases

- "BoutiqueDB open options"
- "TursoOpenOptions"
- "experimental features BoutiqueDB"
- "asyncIO"
- "BoutiqueDB encryption"
- "multiProcess WAL BoutiqueDB"
- "BoutiqueDB FTS"
- "BoutiqueDB vector search"
- "BoutiqueDB materialized views"

## Workflow

1. **Explain the default**: `.tursoEnhanced` enables `views`, `index_method`, `generated_columns`, `vacuum`, `without_rowid`. `.tursoEnhancedAsync` also enables cooperative `async_io`.
2. **List official experimental tokens**:
   `views` · `custom_types` · `encryption` · `index_method` · `autovacuum` · `vacuum` · `attach` · `generated_columns` · `without_rowid` · `multiprocess_wal` · `mvcc_passive_checkpoint`.
3. **Provide feature-specific examples**:
   ```swift
   // Minimal
   let db = try BoutiqueDB(url: url, openOptions: TursoOpenOptions())

   // Async I/O
   let db = try BoutiqueDB(url: url, openOptions: .tursoEnhancedAsync)

   // Encryption with Keychain key
   let key = try loadKeyFromKeychain()  // 32 bytes
   let db = try BoutiqueDB(
     url: url,
     encryption: .aegis256(key: key)
   )

   // Multi-process WAL for App Group / extension sharing
   let db = try BoutiqueDB(url: url, multiProcess: true)
   ```
4. **Explain `asyncIO` modes**: `false` loops `TURSO_IO` synchronously; `true` suspends with `Task.yield()` between I/O ticks.
5. **Turso feature usage**:
   - FTS: `@BoutiqueTable @FTSIndex("title", "body")` + `.match(query)`/`.score(query)`.
   - Vector: `Vector32` + `@VectorIndex("embedding", metric: .cosine)` + `vectorDistanceCos(...)`.
   - Materialized views: `@MaterializedView(name:as:)`.
   - Generated columns, `STRICT`, `WITHOUT ROWID`: `@BoutiqueTable` options.
6. **Warn about stability**: experimental features may panic or produce incorrect results; gate runtime usage on `db.capabilities.ftsIndex`, `vectorIndex`, `materializedViews`, etc.
7. **Reference docs**:
   - `docs/getting-started/open-options.md`
   - `docs/advanced/experimental-features.md`
   - `docs/advanced/sdk-kit-c-abi.md`
   - `docs/turso-features-in-apple-apps.md`
   - `docs/performance-tuning.md`
