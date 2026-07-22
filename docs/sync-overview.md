# Sync possibilities

BoutiqueDB separates persistence from sync. The local database is always authoritative while the app is offline; sync adapters move changes to and from a remote store when connectivity is available.

## CloudKit sync (default)

`TursoCKSync` maps CDC change records from the local database to CloudKit records. It uses `CKSyncEngine` and is designed for private-database, per-user sync.

What it provides:

- One local row maps to one CloudKit record.
- Inserts, updates, and deletes are captured from `turso_cdc`.
- Conflict resolution is delegated to CloudKit with configurable policies.
- Account switches preserve local rows and reset sync metadata.

Requirements:

- iCloud + CloudKit entitlements.
- Push Notifications + `remote-notification` background mode.
- An explicit `CKContainer` or container identifier.
- `BoutiqueDBSyncEngine.attach(to:automaticallyDrain: true)` after opening the database.

See [CloudKit sync guide](guides/cloudkit-sync) and the [CloudKit QA checklist](contributors/spi-checklist).

## Turso Cloud sync (future adapter)

The engine includes a sync protocol (`sync/engine` and `sync/sdk-kit`) that can pull and push WAL changes over HTTP. BoutiqueDB exposes a `SyncAdapter` protocol so a future adapter can plug into the same `BoutiqueDB` container without changing the local schema or query APIs.

The sync protocol supports:

- Push of local CDC operations to a remote endpoint.
- Pull of remote page updates or logical MVCC changes.
- Partial bootstrap with prefix or query-based lazy page loading.
- Remote encryption keys for cloud-encrypted databases.

At this time, the framework ships with `CloudKitSyncAdapter` only. A Turso Cloud adapter is not included in the current beta.

## Custom sync adapters

You can implement `SyncAdapter` to connect BoutiqueDB to any backend:

```swift
public protocol SyncAdapter {
  func applyRemoteChanges(_ changes: SyncChangeSet) async throws
  func fetchRemoteChanges(since: SyncToken) async throws -> SyncChangeSet
}
```

Attach an adapter with `BoutiqueDB.attachSyncAdapter(_:)`.

## CDC and sync safety

CDC (`PRAGMA capture_data_changes_conn`) writes every local change to `turso_cdc`. The sync engine drains that table, maps rows, and clears successfully applied operations. If sync falls behind, the CDC table grows; checkpointing and retention are handled by the engine.

> **Note:** CDC and MVCC are mutually exclusive on the same connection. BoutiqueDB uses MVCC on a separate concurrent writer and CDC on the primary handle, or falls back to immediate transactions if that combination is rejected by the engine build.
