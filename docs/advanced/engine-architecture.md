# Engine architecture

The BoutiqueDB engine is a Rust rewrite of SQLite. It keeps the SQLite file format and SQL dialect but replaces the query execution, storage, and I/O layers with Rust code.

## High-level components

| Component | Location in engine repo | Responsibility |
|-----------|------------------------|----------------|
| SQL parser | `sqlite/parser/src/parser.rs` | Recursive-descent parser, lexer, AST |
| Query compiler / optimizer | `core/translate/` and `core/translate/optimizer/` | AST → VDBE bytecode, query plans |
| Virtual machine | `core/vdbe/execute.rs` | Bytecode interpreter |
| B-tree / pages | `core/storage/btree.rs` | SQLite-compatible page format |
| WAL / durability | `core/storage/wal.rs` | Write-ahead log, checkpointing |
| Async I/O | `core/io/` | `io_uring`, syscall, Windows IOCP backends |
| MVCC | `core/mvcc/` and `docs/internals/mvcc/` | Multi-version concurrency control |

## Compilation pipeline

```text
SQL → Parser → AST → Translator/Optimizer → VDBE bytecode → Execute
```

The VDBE (Virtual Database Engine) is a register-based virtual machine similar to SQLite’s. Its bytecode is general enough to host multiple frontends; SQLite is the primary frontend, and Postgres is an experimental frontend.

## I/O model

The engine supports pluggable I/O backends:

- `syscall` — generic blocking file I/O.
- `io_uring` — Linux kernel-queued async I/O.
- `experimental_win_iocp` — Windows I/O completion ports.

With `async_io` enabled, the engine returns `TURSO_IO` from `step()` and expects the caller to drive `run_io()` until the operation completes.

## Storage compatibility

- Page size defaults to 4096 bytes.
- The on-disk format is SQLite-compatible for standard tables and indexes.
- Turso-only features (custom index methods, generated columns, materialized views, custom types) may write extra state that SQLite does not understand.

For more detail, see the engine repo’s `docs/agent-guides/` and `docs/internals/mvcc/`.
