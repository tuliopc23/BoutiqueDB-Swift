# CloudKit Sync — Manual QA Checklist

Use this for release candidates. Automated tests cover the offline path (`enablesCloudKit: false`). Live CloudKit requires a signed iCloud account and app entitlements.

## Prerequisites

- [ ] Two physical devices signed into the **same** iCloud test account
- [ ] App has iCloud + CloudKit capability and a container ID matching `TursoCKSyncConfiguration.containerIdentifier`
- [ ] Build links the packaged `TursoSDK.xcframework` and opens with CDC enabled
- [ ] `enablesCloudKit: true` in the sample / QA build

## Happy path (two devices)

1. Install build on Device A and Device B.
2. On A, create a note (or row in each synced table).
3. Wait ≤ 30 s (or pull-to-sync if exposed).
4. **Expect:** row appears on B with matching fields and PK.
5. Edit the same row on B.
6. **Expect:** A receives the update (per conflict policy).
7. Delete on A.
8. **Expect:** row disappears on B.

## Multi-table

1. Insert into **two** `syncedTables` on A.
2. **Expect:** both record types appear on B (`table:rowPK` record names).

## Account change

1. On A, sign out of iCloud (or switch accounts).
2. **Expect:** app remains usable with **local data preserved**; sync status may show `accountChanged` then rebootstrap.
3. Sign back in.
4. **Expect:** local rows re-upload; second device eventually converges.

## Zone / network faults

1. Disable network mid-sync.
2. **Expect:** `SyncStatus.failed` or retry without corruption; no crash.
3. Re-enable network; drain / auto-sync.
4. **Expect:** pending changes flush; no duplicate primary keys.

## Batching (large write)

1. Insert ≥ 600 rows locally.
2. **Expect:** outbound send uses batches ≤ 250 records; CDC drain steps of ≤ 500.
3. **Expect:** peer device eventually receives all rows.

## Conflict policy spot-checks

| Policy | Setup | Expect |
|---|---|---|
| `.serverWins` | Concurrent edit A then B | B’s value (or last server) wins |
| `.clientWins` | Concurrent edit | Local re-pends after absorbing system fields |
| `.lastWriterWins(field: "updatedAt")` | Stagger `updatedAt` | Newer timestamp wins |

## Sign-off

| Build | Tester | Date | Result |
|---|---|---|---|
| | | | |

See also: [Sync benchmarks](sync-benchmarks.md).
