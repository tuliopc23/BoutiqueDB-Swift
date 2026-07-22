# Sync protocol

The engine includes a sync engine (`sync/engine`) that can replicate a SQLite-compatible database between a client and a server. The protocol is used by `sync/sdk-kit` and exposed through `turso_sync.h`.

## Overview

The sync engine maintains:

- A main database file.
- A WAL for local writes.
- A revert WAL for rolling back remote changes.
- A changes file for pending CDC operations.
- A metadata file with server URL, client ID, and sync state.

## Client-side API

The `turso_sync.h` header defines a state-machine API around `turso_sync_database_t` and `turso_sync_operation_t`:

```c
turso_sync_database_new(&db_config, &sync_config, &sync_db, &error);
turso_sync_database_create(sync_db, &op, &error);

// Drive operations
for (;;) {
  turso_status_t st = turso_sync_operation_resume(op, &error);
  if (st.code == TURSO_IO) { /* handle HTTP or file IO */ }
  else if (st.code == TURSO_DONE) { break; }
}
```

## IO request types

The sync engine returns IO requests of type:

- `TURSO_SYNC_IO_HTTP` — perform an HTTP request and push the response body.
- `TURSO_SYNC_IO_FULL_READ` — atomically read a local file.
- `TURSO_SYNC_IO_FULL_WRITE` — atomically write a local file.

The host app is responsible for the actual network call or file operation and then calling `turso_sync_database_io_done()` or poisoning the request on error.

## Server endpoints

A sync server implements:

- `POST /v2/pipeline` — SQL-over-HTTP (Hrana) commands encoded as JSON.
- `POST /pull-updates` — returns length-delimited protobuf messages with WAL page updates.

The `/pull-updates` endpoint streams a `PullUpdatesResponseHeader` followed by `PullUpdatesPageData` messages. Server and client use zero-based page numbers.

## Logical MVCC pull

For MVCC-mode remotes, set `logical_mvcc_pull` in the sync config. The client then reads the MVCC logical-log stream instead of the page stream.

## Integration with BoutiqueDB

BoutiqueDB does not ship a sync engine adapter in the current beta. The `SyncAdapter` protocol is the intended seam for a future adapter that drives `sync/sdk-kit` over the host’s networking stack.
