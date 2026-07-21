# TursoCloudKit

Local-first stack: **Turso Database** file on device + Apple **`CKSyncEngine`** (CloudKit private DB). No Turso Cloud, no SQLiteData/GRDB.

## Modules

| Product | Role |
|---------|------|
| `TursoKit` | Embed Turso C API; open `.db`; CRUD; `PRAGMA capture_data_changes_conn('full')` |
| `StructuredQueriesTurso` | `execute` / `fetchAll` / `fetchOne` for `@Table` models |
| `TursoCKSync` | CDC → pending CloudKit changes; inbound apply; `stateSerialization`; conflicts / account |
| `TursoObservation` | CDC poll / invalidate helper for SwiftUI |

## Build Turso (once)

```bash
git clone https://github.com/tursodatabase/turso ../turso-src   # if needed
./Scripts/build-turso.sh
```

Requires Rust (`cargo`) and Xcode. Produces `Vendor/TursoSQLite3.xcframework`.

## Quick start

```swift
import TursoKit
import TursoCKSync
import StructuredQueriesTurso

let url = try TursoDatabase.applicationSupportURL()
let conn = try TursoDatabase(url: url).connect(enableCDC: true)

try conn.execute("""
  CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    updatedAt TEXT NOT NULL
  )
""")

let sync = try TursoCKSyncEngine(
  connection: conn,
  configuration: .init(
    containerIdentifier: "iCloud.com.example.app", // required for production
    syncedTables: [
      SyncedTable(name: "notes", columns: ["title", "body", "updatedAt"])
    ],
    enablesCloudKit: true // set false only for local unit tests without entitlements
  )
)
try sync.start()

try sync.performLocalWrite {
  try conn.execute(
    "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
    [.text(UUID().uuidString), .text("Hi"), .text(""), .text(ISO8601DateFormatter().string(from: Date()))]
  )
}
```

### App setup

- Entitlements: iCloud + CloudKit container; Background Modes → remote notifications
- Init `TursoCKSyncEngine` early at launch (loads persisted `stateSerialization`)
- Call `drainCDC()` / `performLocalWrite` after local mutations
- Sync connection must **not** use `journal_mode=mvcc` (CDC ⊥ MVCC)

### What is not synced

`turso_cdc`, `ck_*` metadata tables, materialized views, oversized blobs.

## Tests

```bash
swift test
```

Round-trip coverage uses a **simulated** two-device path (A builds `CKRecord` → B applies) with `enablesCloudKit: false` so `swift test` does not need entitlements. Live two-simulator CloudKit needs a signed-in iCloud account, an app target with iCloud+CloudKit entitlements, and `enablesCloudKit: true`.

**Tip:** Prefer UUID/`TEXT` primary keys. Turso CDC’s `id` column may be the integer `rowid`; the bridge resolves the configured PK via `rowid` lookup / decoded `after` payload.

## Layout

```
Sources/TursoKit/
Sources/StructuredQueriesTurso/
Sources/TursoCKSync/
Sources/TursoObservation/
Vendor/TursoSQLite3.xcframework
```
