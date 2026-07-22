# SDK-kit C ABI

BoutiqueDB links the engine through the `sdk-kit` C ABI (`turso.h`). This is the official surface for building language bindings, and it is the only surface that exposes `async_io`, per-open experimental features, and encryption.

## Why `sdk-kit` instead of `sqlite3.h`

The `bindings/c` crate implements the SQLite 3 C API for compatibility. It is useful for dropping BoutiqueDB into existing SQLite code, but it has limits:

- The only experimental toggle is global `turso_enable_experimental()`, which enables a subset of flags.
- It cannot set `async_io` per open.
- It cannot configure encryption keys per database.

`sdk-kit` (`sdk-kit/turso.h`) exposes a small, explicit C surface designed for bindings.

## Key types and functions

### Database lifecycle

```c
turso_database_config_t config = {
  .path = ":memory:",
  .experimental_features = "views,index_method",
  .async_io = true,
  .vfs = NULL,
  .encryption_cipher = NULL,
  .encryption_hexkey = NULL
};

turso_database_new(&config, &db, &error);
turso_database_open(db, &error);
turso_database_connect(db, &conn, &error);
```

### Statement loop

```c
for (;;) {
  turso_status_t st = turso_statement_step(stmt, &error);
  if (st.code == TURSO_ROW) { /* read row */ }
  else if (st.code == TURSO_DONE) { break; }
  else if (st.code == TURSO_IO) { turso_statement_run_io(stmt, &error); }
  else { /* error */ }
}
```

### Status codes

- `TURSO_OK`, `TURSO_DONE`, `TURSO_ROW`
- `TURSO_IO` — drive I/O and resume.
- `TURSO_BUSY` — conflict or lock contention.
- `TURSO_BUSY_SNAPSHOT` — MVCC snapshot conflict.
- `TURSO_ERROR` — general error; check `error_opt_out`.

## Swift mapping

`TursoKit` wraps these C calls into Swift types:

| C type | Swift type |
|--------|-----------|
| `turso_database_t` | `TursoDatabase` |
| `turso_connection_t` | `TursoConnection` |
| `turso_statement_t` | `TursoStatement` |
| `turso_value_t` | `TursoValue` |

`TursoOpenOptions` maps to `turso_database_config_t`.

For the full C API, see `sdk-kit/turso.h` in the engine repo.
