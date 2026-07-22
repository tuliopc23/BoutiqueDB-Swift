# Testing

BoutiqueDB can be tested with the Swift Testing framework or XCTest. The key is to use isolated, in-memory or temporary-file databases per test.

## Unit tests with `BoutiqueDB`

```swift
import BoutiqueDB
import Testing

@Test
func insertsAndQueriesNotes() async throws {
  let url = URL(fileURLWithPath: "/tmp/boutiquedb-test-\(UUID().uuidString).db")
  let db = try await BoutiqueDB.open(url: url, migrations: AppMigrations.plan)

  try await db.write { conn in
    try conn.execute(
      "INSERT INTO notes (id, title) VALUES (?, ?)",
      [.text("1"), .text("Test")]
    )
  }

  let count = try await db.read { conn in
    try Note.all.fetchCount(conn)
  }

  #expect(count == 1)
}
```

## Test against a local engine build

If you are iterating on the engine itself, point the package at a local `Vendor/TursoSDK.xcframework`:

```bash
# Build the engine into the package checkout
./Scripts/build-turso-sdk-xcframework.sh
BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
```

## Testing CloudKit sync

- Use the CloudKit development environment.
- Test on a physical device with a signed-in iCloud account before shipping.
- The simulator is useful for unit tests but does not validate push-driven sync.

## Snapshot testing

`BoutiqueDBTests` uses `swift-snapshot-testing` for macro output and query generation snapshots. Run them with `swift test`.

## Test isolation

- Create a unique database file per test.
- Clean up files in `tearDown` or use a temporary directory.
- Do not share a `BoutiqueDB` instance across tests that write data.
