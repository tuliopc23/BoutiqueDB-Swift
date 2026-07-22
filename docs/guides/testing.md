# Testing

BoutiqueDB can be tested with the Swift Testing framework or XCTest. The key is to use isolated, temporary-file databases per test.

## Unit tests with `BoutiqueDB`

```swift
import BoutiqueDB
import Testing

@Test
func insertsAndQueriesNotes() async throws {
  let url = URL(fileURLWithPath: "/tmp/boutiquedb-test-\(UUID().uuidString).db")
  let db = try await BoutiqueDB.open(url: url, migrations: AppMigrations.plan)
  defer {
    db.close()
    try? FileManager.default.removeItem(at: url)
  }

  try await db.write { conn in
    try conn.execute(
      "INSERT INTO notes (id, title) VALUES (?, ?)",
      [.text("1"), .text("Test")]
    )
  }

  let count = try await db.read { conn in
    try Note.all.fetchCount(conn.connection)
  }

  #expect(count == 1)
}
```

## Test helpers

Create a helper that every test calls:

```swift
func openTestDB(
  migrations: BoutiqueMigrationPlan = AppMigrations.plan,
  startListening: Bool = false
) throws -> BoutiqueDB {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("bd-test-\(UUID().uuidString).db")
  return try BoutiqueDB(
    url: url,
    startListening: startListening,
    openOptions: .tursoEnhanced,
    migrations: migrations
  )
}
```

## Test against a local engine build

If you are iterating on the engine itself, point the package at a local `Vendor/TursoSDK.xcframework`:

```bash
# Build the engine into the package checkout
./Scripts/build-turso-sdk-xcframework.sh
BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
```

For a single debug slice:

```bash
SLICES=macos-arm64 ./Scripts/build-turso-sdk-xcframework.sh
BOUTIQUE_LOCAL_TURSO_SDK=1 swift test
```

Never ship single-slice binaries.

## Testing CloudKit sync

- Use the CloudKit development environment.
- Test on a physical device with a signed-in iCloud account before shipping.
- The simulator is useful for unit tests but does not validate push-driven sync.
- Use `enablesCloudKit: false` in unit tests to avoid entitlements.

## LiveQuery tests

Use `store.advanceFromCDC()` to trigger a refresh synchronously:

```swift
let query = LiveQuery(db) { Note.all.asSelect() }
_ = await waitFor { !query.isLoading }

try await db.write { conn in
  try Note.insert { Note(id: UUID(), title: "T", body: "") }
    .execute(conn.connection)
}

query.forceRefresh()
_ = await waitFor { query.wrappedValue.count == 1 }
```

## Test isolation

- Create a unique database file per test.
- Call `db.close()` and delete files in `defer`.
- Do not share a `BoutiqueDB` instance across tests that write data.
- Use `startListening: false` unless you are testing observation.
