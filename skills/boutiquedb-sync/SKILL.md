---
name: boutiquedb-sync
description: |
  Guides CloudKit sync setup, the SyncAdapter protocol, and the engine sync protocol for BoutiqueDB.
  Use when the user asks about "BoutiqueDB CloudKit", "sync", "CKSyncEngine",
  "BoutiqueDBSyncEngine", "sync adapter", or "Turso Cloud sync".
---

# BoutiqueDB sync

Help the user understand and configure sync in BoutiqueDB. Default is CloudKit private-database sync via `CKSyncEngine`; custom adapters are possible.

## Trigger phrases

- "BoutiqueDB CloudKit"
- "BoutiqueDB sync"
- "CKSyncEngine"
- "BoutiqueDBSyncEngine"
- "sync adapter"
- "Turso Cloud sync BoutiqueDB"

## Workflow

1. **Identify the sync target**: CloudKit (default), custom `SyncAdapter`, or future Turso Cloud.
2. **For CloudKit**, list prerequisites**:
   - iCloud + CloudKit entitlements.
   - Push Notifications + `remote-notification` background mode.
   - Explicit `CKContainer` identifier or injected `CKContainer`.
3. **Provide correct setup code**:
   ```swift
   let db = try await BoutiqueDB.open(
     url: BoutiqueDB.applicationSupportURL(),
     migrations: AppMigrations.plan
   )

   let syncEngine = try BoutiqueDBSyncEngine(
     db: db,
     containerIdentifier: "iCloud.com.example.myapp",
     syncedTables: [
       try SyncedTable(
         schema: NoteSchema.self,
         recordType: "Note"
       )
     ],
     conflictPolicy: .lastWriterWins(field: "updatedAt")
   )
   syncEngine.attach(to: db, automaticallyDrain: true)
   Task {
     try await syncEngine.start()
   }

   // Observe status
   Task {
     for await status in syncEngine.syncStatus() {
       switch status { ... }
     }
   }
   ```
4. **Synced table constraints**:
   - Single-column primary key (UUID or string).
   - No `AUTOINCREMENT`.
   - No compound primary keys.
   - No unique indexes besides the PK.
5. **Explain CDC**: local changes are captured in `turso_cdc`, drained by `BoutiqueDBSyncEngine`, mapped to `CKRecord`, and uploaded by `CKSyncEngine`.
6. **Explain `SyncAdapter`** for custom backends:
   ```swift
   public protocol SyncAdapter: AnyObject, Sendable {
     func start() async throws
     func stop() async
     func syncStatus() -> AsyncStream<SyncStatus>
     func drainLocalChanges() async throws -> Int
     func fetchChanges() async throws
     func sendChanges() async throws
     func syncChanges() async throws
     func applyRemoteChanges(_ changes: [RemoteChange]) async throws
   }
   ```
7. **Mention MVCC/CDC rule**: CDC and MVCC are mutually exclusive on the same connection; `BoutiqueDB` uses the safe busy-retry path when both are requested.
8. **Reference docs**:
   - `docs/sync-overview.md`
   - `docs/guides/cloudkit-sync.md`
   - `docs/advanced/sync-protocol.md`
   - `docs/contributors/cloudkit-qa-checklist.md`
