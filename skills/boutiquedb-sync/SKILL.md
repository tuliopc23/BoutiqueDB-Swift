---
name: boutiquedb-sync
description: |
  Guides CloudKit sync setup, the SyncAdapter protocol, and the engine sync protocol.
  Use when the user asks about "BoutiqueDB CloudKit", "sync", "CKSyncEngine",
  "BoutiqueDBSyncEngine", "sync adapter", or "Turso Cloud sync".
---

# BoutiqueDB sync

Help the user understand and configure sync in BoutiqueDB.

## Trigger phrases

- "BoutiqueDB CloudKit"
- "BoutiqueDB sync"
- "CKSyncEngine"
- "BoutiqueDBSyncEngine"
- "sync adapter"
- "Turso Cloud sync BoutiqueDB"

## Workflow

1. **Identify the sync target**: CloudKit (default), custom `SyncAdapter`, or future Turso Cloud.
2. **For CloudKit**, list prerequisites:
   - iCloud + CloudKit entitlements.
   - Push Notifications + `remote-notification` background mode.
   - Explicit `CKContainer` identifier.
3. **Provide setup code**:
   ```swift
   let syncEngine = BoutiqueDBSyncEngine(
     container: CKContainer(identifier: "iCloud.com.example.myapp")
   )
   try syncEngine.attach(to: db, automaticallyDrain: true)
   ```
4. **Explain CDC**: local changes are captured in `turso_cdc`, drained by `TursoCKSync`, mapped to `CKRecord`, and uploaded by `CKSyncEngine`.
5. **Explain `SyncAdapter`** for custom backends:
   ```swift
   public protocol SyncAdapter {
     func applyRemoteChanges(_ changes: SyncChangeSet) async throws
     func fetchRemoteChanges(since: SyncToken) async throws -> SyncChangeSet
   }
   ```
6. **Mention MVCC/CDC rule**: CDC and MVCC are mutually exclusive on the same connection; BoutiqueDB handles the fallback.
7. **Reference docs**:
   - `docs/sync-overview.md`
   - `docs/guides/cloudkit-sync.md`
   - `docs/advanced/sync-protocol.md`
   - `docs/contributors/cloudkit-qa-checklist.md`
