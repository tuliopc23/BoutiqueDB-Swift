# CloudKit sync

`TursoCKSync` bridges BoutiqueDB change records and `CKSyncEngine`. It is designed for per-user private database sync.

## Setup

1. Enable **iCloud** and **CloudKit** in your app entitlements.
2. Add **Push Notifications** and the `remote-notification` background mode.
3. Provide a `CKContainer` identifier or inject a `CKContainer`.
4. Add an `updatedAt` (or similar) field if you want `lastWriterWins` conflict resolution.

```swift
import BoutiqueDB
import CloudKit

@Table
struct Note: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
  var updatedAt: Date
}

let db = try await BoutiqueDB.open(
  url: BoutiqueDB.applicationSupportURL(),
  migrations: AppMigrations.plan
)

let syncEngine = try BoutiqueDBSyncEngine(
  db: db,
  containerIdentifier: "iCloud.com.example.myapp",
  syncedTables: [
    try SyncedTable(
      name: "notes",
      primaryKeyColumn: "id",
      columns: ["title", "body", "updatedAt"]
    )
  ],
  conflictPolicy: .lastWriterWins(field: "updatedAt")
)
syncEngine.attach(to: db, automaticallyDrain: true)
Task {
  try await syncEngine.start()
}
```

## How sync works

- Local commits are captured in `turso_cdc`.
- `BoutiqueDBSyncEngine` drains CDC rows and maps them to `CKRecord` objects.
- `CKSyncEngine` uploads new/modified records and downloads remote changes.
- Remote changes are applied to the local database through the normal `write` path.

## `SyncedTable` from `BoutiqueSchema`

If you use `@BoutiqueTable`, you can derive `SyncedTable` from the schema:

```swift
@BoutiqueTable
struct NoteSchema: Sendable {
  @Column(primaryKey: true) let id: UUID
  var title: String
  var body: String
  var updatedAt: Date
}

let synced = try SyncedTable(schema: NoteSchema.self, recordType: "Note")
```

## Conflict handling

```swift
let syncEngine = try BoutiqueDBSyncEngine(
  db: db,
  syncedTables: [...],
  conflictPolicy: .lastWriterWins(field: "updatedAt")
)
```

Policies:

- `.serverWins` — remote record overwrites local changes.
- `.clientWins` — re-pend the local save.
- `.lastWriterWins(field:)` — compare a timestamp or version column.

## Account switches

When the user signs out or switches iCloud accounts:

- Local rows are preserved.
- Sync metadata is reset.
- The host app is responsible for account UI and policy.

Call `noteAccountIdentity` with a stable hash of the signed-in Apple ID to detect changes.

## Status observation

```swift
Task {
  for await status in syncEngine.syncStatus() {
    switch status {
    case .idle: break
    case .syncing: showProgress()
    case .failed(let message): showError(message)
    case .needsAuthentication: showSignIn()
    case .accountChanged: showAccountChanged()
    }
  }
}
```

## QA checklist

See the [CloudKit QA checklist](../contributors/cloudkit-qa-checklist) for production validation steps.

## Limitations

- Sharing and public CloudKit databases are not supported in the current beta.
- Sync must be tested on a physical device with a production iCloud account for final validation; the simulator is useful for development but not sufficient.
- Tables with `AUTOINCREMENT`, compound primary keys, or non-unique indexes cannot be synced.
