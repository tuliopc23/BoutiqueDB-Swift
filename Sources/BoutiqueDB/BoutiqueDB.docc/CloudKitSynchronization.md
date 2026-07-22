# CloudKit Synchronization

Synchronize explicitly selected local tables with a private CloudKit database.

## Host application requirements

The host app owns signing and must enable iCloud/CloudKit, Push Notifications,
and the `remote-notification` background mode. Pass an explicit container
identifier or an injected `CKContainer`; BoutiqueDB never falls back to a
development container. If sharing is added by the host, also enable
`CKSharingSupported` and handle accepted shares in the app scene delegate.

Create all tables and finish migrations before constructing
`TursoCKSyncEngine`. A synchronized table needs one non-autoincrement primary
key, no additional unique constraints, compatible CloudKit field names, and an
append-only schema. Engine startup validates these invariants.

```swift
let sync = try TursoCKSyncEngine(
  connection: database.unsafeConnection,
  configuration: .init(
    containerIdentifier: "iCloud.com.example.app",
    syncedTables: [
      SyncedTable(name: "notes", columns: ["title", "body", "updatedAt"])
    ]
  )
)
let adapter = CloudKitSyncAdapter(engine: sync)
try await adapter.start()
```

Automatic CKSyncEngine scheduling is intentionally nondeterministic. Use
`fetchChanges`, `sendChanges`, or `syncChanges` for explicit user actions such
as pull-to-refresh, not as a replacement for background scheduling.

## Account and conflict policy

Account switches preserve local user rows and reset sync metadata. Hosts should
observe `SyncStatus.accountChanged` and decide what account-specific UI or
data policy to present. Conflict policy can be server-wins, client-wins, or
last-writer-wins using a comparable field. Client-wins preserves the local
payload while adopting server system fields for the retry.

## Validation boundary

Offline tests cover durable outbox restart, conflicts, echo suppression,
partial acknowledgements, schema rejection, and simulated two-device exchange.
Remote notification delivery and real account behavior require signed physical
devices against the production CloudKit environment; simulators are not a
release substitute.

BoutiqueDB currently synchronizes the private database. Public-database sync and
a complete CKShare lifecycle are not advertised by this beta.
