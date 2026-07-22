# Differences from a SQLite-backed engine

BoutiqueDB’s underlying engine is a Rust rewrite of SQLite (Turso). It is file- and dialect-compatible, but it is not a thin wrapper around `libsqlite3`. The differences matter for performance, concurrency, and feature availability.

## File format compatibility

SQLite database files open in BoutiqueDB and vice versa. The on-disk page format is shared, so you can migrate a `.db` file without export/import. The WAL format is engine-specific, so a live WAL from one engine should not be mixed with the other.

> **Warning:** Do not enable Turso-only experimental features on a database you intend to open with stock SQLite. Some features (custom types, generated columns, materialized views, vector indexes) write schema or indexes that SQLite may not understand.

## Query execution model

SQLite evaluates SQL opcodes directly inside its virtual machine. Turso compiles SQL into bytecode for a similar VDBE, but the bytecode interpreter, B-tree layer, and I/O scheduler are written in Rust and support cooperative async I/O.

Consequences:

- `async_io` lets the engine yield at I/O boundaries, so long writes do not block Swift concurrency.
- The same `DatabaseActor` can drive engine I/O without blocking the main thread.
- Bytecode can be compared with `EXPLAIN` for compatibility testing.

## Concurrency

SQLite in WAL mode allows one writer and multiple readers. Turso adds:

- `BEGIN CONCURRENT` (MVCC) for optimistic multi-writer transactions with snapshot isolation.
- `PRAGMA journal_mode = mvcc` for MVCC mode.
- A multi-process WAL sidecar for sharing a database across process boundaries.

BoutiqueDB uses a dedicated MVCC connection for `concurrentWrites` and falls back to busy-retry immediate transactions if MVCC is unavailable for a given handle.

## Feature matrix

| Feature | SQLite | BoutiqueDB engine |
|---------|--------|-------------------|
| File format | `.db` | `.db` (same) |
| SQL dialect | SQLite | SQLite + opt-in extensions |
| Async I/O | Blocking | `async_io` cooperative |
| `BEGIN CONCURRENT` / MVCC | No | Yes (opt-in) |
| Full-text search | FTS5 | Tantivy-backed `USING fts` |
| Vector search | No | `USING vector` + vector functions |
| Materialized views | No | Incremental view maintenance (IVM) |
| Custom types / domains | No | `CREATE TYPE`, `CREATE DOMAIN` |
| Encryption at rest | SQLCipher-style | `aegis256`, `chacha20poly1305` |
| Multi-process WAL | No | `.tshm` sidecar |

## C ABI surface

BoutiqueDB uses the `sdk-kit` C ABI (`turso.h`) rather than the `sqlite3.h` compatibility surface. The `sdk-kit` surface exposes:

- Explicit `turso_database_config_t` with `experimental_features`, `async_io`, `vfs`, and encryption fields.
- Status-driven `step`/`run_io` loops instead of hidden blocking calls.
- Clear ownership rules for `database`, `connection`, and `statement` handles.

The `sqlite3` surface exists for compatibility but cannot toggle most experimental flags per open.

## Backwards compatibility guarantees

Turso’s compatibility guarantees apply:

1. You can always return to SQLite if you do not use incompatible features.
2. You can open a SQLite-created database in BoutiqueDB.
3. Incompatible features are opt-in.
4. Mixed-engine multi-process access is not supported.
