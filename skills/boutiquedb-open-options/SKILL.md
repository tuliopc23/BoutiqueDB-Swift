---
name: boutiquedb-open-options
description: |
  Explains TursoOpenOptions, experimental feature tokens, async I/O, encryption, and capability probes.
  Use when the user asks about "BoutiqueDB open options", "experimental features",
  "TursoOpenOptions", "asyncIO", "encryption", "multiProcess", or "capability probe".
---

# BoutiqueDB open options

Explain how `TursoOpenOptions` maps to the official `sdk-kit` engine configuration and how to enable experimental features safely.

## Trigger phrases

- "BoutiqueDB open options"
- "TursoOpenOptions"
- "experimental features BoutiqueDB"
- "asyncIO"
- "BoutiqueDB encryption"
- "multiProcess WAL BoutiqueDB"

## Workflow

1. **Explain the default**: `.tursoEnhanced` enables `views`, `index_method`, `generated_columns`, `vacuum`, `without_rowid`.
2. **List official experimental tokens**:
   `views` · `custom_types` · `encryption` · `index_method` · `autovacuum` · `vacuum` · `attach` · `generated_columns` · `without_rowid` · `multiprocess_wal` · `mvcc_passive_checkpoint`.
3. **Provide examples**:
   ```swift
   // Minimal
   let db = try BoutiqueDB(url: url, openOptions: TursoOpenOptions())

   // Async I/O
   let db = try BoutiqueDB(url: url, openOptions: .tursoEnhancedAsync)

   // Encryption
   let db = try BoutiqueDB(
     url: url,
     encryption: .aegis256(key: keyData)
   )

   // Multi-process WAL for App Group / extensions
   let db = try BoutiqueDB(url: url, multiProcess: true)
   ```
4. **Explain `asyncIO` modes**: `false` loops `TURSO_IO` internally; `true` suspends with `Task.yield()`.
5. **Warn about stability**: experimental features may panic or produce incorrect results; gate on `TursoCapabilities.probe` where needed.
6. **Reference docs**:
   - `docs/getting-started/open-options.md`
   - `docs/advanced/experimental-features.md`
   - `docs/advanced/sdk-kit-c-abi.md`
