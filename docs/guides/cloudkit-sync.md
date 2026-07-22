# CloudKit sync

`TursoCKSync` bridges BoutiqueDB change records and `CKSyncEngine`. It is designed for per-user private database sync.

## Setup

1. Enable **iCloud** and **CloudKit** in your app entitlements.
2. Add **Push Notifications** and the `remote-notification` background mode.
3. Provide a `CKContainer` identifier or inject a `CKContainer`.

```swift
import BoutiqueDB
import CloudKit

let configuration = BoutiqueDBConfiguration(
  url: BoutiqueDB.applicationSupportURL(),
  migrations: AppMigrations.plan
)

let db = try await BoutiqueDB.open(configuration)

let syncEngine = BoutiqueDBSyncEngine(
  container: CKContainer(identifier: "iCloud.com.example.myapp")
)

try syncEngine.attach(to: db, automaticallyDrain: true)
```

## How sync works

- Local commits are captured in `turso_cdc`.
- `BoutiqueDBSyncEngine` drains CDC rows and maps them to `CKRecord` objects.
- `CKSyncEngine` uploads new/modified records and downloads remote changes.
- Remote changes are applied to the local database through the normal `write` path.

## Conflict handling

Conflicts are resolved by CloudKit according to the record zone policy. The local adapter does not implement custom merge logic by default. You can override the `ConflictPolicy` when you initialize the sync engine.

## Account switches

When the user signs out or switches iCloud accounts:

- Local rows are preserved.
- Sync metadata is reset.
- The host app is responsible for account UI and policy.

## QA checklist

See the [CloudKit QA checklist](../contributors/spi-checklist) for production validation steps.

## Limitations

- Sharing and public CloudKit databases are not supported in the current beta.
- Sync must be tested on a physical device with a production iCloud account for final validation; the simulator is useful for development but not sufficient.
