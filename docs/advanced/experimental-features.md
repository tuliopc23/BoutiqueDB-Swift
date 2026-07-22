# Experimental features

The Turso engine exposes several opt-in features. BoutiqueDB surfaces them through `TursoOpenOptions` and probes them through `db.capabilities`.

## Official feature tokens

The engine recognizes the following tokens in the `experimental_features` comma-separated string:

- `views` — materialized views and incremental view maintenance (IVM).
- `custom_types` — `CREATE TYPE` and `CREATE DOMAIN` for `STRICT` tables.
- `encryption` — at-rest encryption (requires cipher and key).
- `index_method` — custom index methods such as `USING fts` and `USING vector`.
- `autovacuum` — auto-vacuum support.
- `vacuum` — `VACUUM` semantics beyond `VACUUM INTO`.
- `attach` — `ATTACH DATABASE` support.
- `generated_columns` — `GENERATED ALWAYS AS` virtual columns.
- `without_rowid` — `WITHOUT ROWID` tables.
- `multiprocess_wal` — cross-process WAL coordination via `.tshm` sidecar.
- `mvcc_passive_checkpoint` — MVCC passive checkpoint behavior.

## Enabling in BoutiqueDB

```swift
let db = try BoutiqueDB(
  url: url,
  openOptions: TursoOpenOptions(
    experimentalFeatures: [.indexMethod, .views, .generatedColumns]
  )
)
```

## Capability probes

Not every engine build includes every feature. `db.capabilities` checks support at runtime:

```swift
if db.capabilities.ftsIndex {
  // safe to create FTS indexes
}
if db.capabilities.vectorIndex {
  // safe to create vector indexes
}
if db.capabilities.materializedViews {
  // safe to create materialized views
}
```

## Stability notes

These features are experimental in the upstream engine:

- MVCC is under active development; indexes are not supported in MVCC mode.
- Materialized views (IVM) have limited SQL support and may reject complex source queries.
- Encryption at rest is not yet recommended for critical data without independent backups.
- Multi-process WAL requires coordination through the `.tshm` sidecar and is only supported on 64-bit Unix and Windows.

> **Warning:** Experimental features may change behavior, produce incorrect results, or panic in edge cases. Enable them only when you need them and test thoroughly.

## Default preset

`TursoOpenOptions.tursoEnhanced` enables `views`, `index_method`, `generated_columns`, `vacuum`, and `without_rowid`. This is the recommended starting point for product apps.

For usage examples, see [Turso features in Apple apps](../turso-features-in-apple-apps).
