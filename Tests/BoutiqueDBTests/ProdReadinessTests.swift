import BoutiqueDB
import CloudKit
import Foundation
import StructuredQueries
import StructuredQueriesTurso
import Testing
import TursoCKSync
import TursoKit
import TursoObservation

extension TursoCKSyncEngine {
  func setInjectedAccountStatus(_ status: CKAccountStatus?) {
    injectedAccountStatus = status
  }
}

@Table
struct PRNote: Sendable {
  @Column(primaryKey: true) let id: String
  var title: String
}

@Suite("Prod readiness")
@MainActor
struct ProdReadinessTests {
  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("pr-\(UUID().uuidString).db")
  }

  @Test func fetchOneMissingReturnsNil() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { await db.close() }
    try await db.execute(
      """
      CREATE TABLE prNotes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    let missing = try await db.fetchOne(PRNote.self, key: "nope")
    #expect(missing == nil)
  }

  @Test func fetchOneFindsRow() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { await db.close() }
    try await db.execute(
      """
      CREATE TABLE prNotes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    try await db.write { conn in
      try await conn.execute(
        "INSERT INTO prNotes (id, title) VALUES ('1','hi')"
      )
    }
    let row = try await db.fetchOne(PRNote.self, key: "1")
    #expect(row?.title == "hi")
  }

  @Test func hasCompletedMigrations() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let plan = BoutiqueMigrationPlan {
      BoutiqueMigration(
        "v1",
        asynchronous: { db in
          try await db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
        })
    }
    let db = try await BoutiqueDB.open(url: url, startListening: false, migrations: plan)
    defer { await db.close() }
    let done = try await BoutiqueMigrator().hasCompletedMigrations(on: db, plan: plan)
    #expect(done)
  }

  @Test func defaultSynchronousMigrationIsAtomic() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    enum Expected: Error { case stop }
    let plan = BoutiqueMigrationPlan {
      BoutiqueMigration(
        "v1",
        migrate: { connection in
          try await connection.execute("CREATE TABLE atomic_default (id INTEGER PRIMARY KEY)")
          throw Expected.stop
        })
    }
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { await db.close() }

    await #expect(throws: BoutiqueError.self) {
      try await db.migrate(using: plan)
    }
    let tableExists = try await db.tableExists("atomic_default")
    let applied = try await db.appliedMigrations()
    #expect(!tableExists)
    #expect(applied.isEmpty)
  }

  @Test func syncedTableDerivesCanonicalSchemaMetadata() throws {
    enum CanonicalNote: BoutiqueSchemaColumns {
      static let boutiqueTableName = "canonical_notes"
      static let boutiqueCreateStatements: [String] = []
      static let boutiqueColumns = [
        BoutiqueColumnSpec(name: "uuid", sqlType: "TEXT", isNullable: false, isPrimaryKey: true),
        BoutiqueColumnSpec(name: "title", sqlType: "TEXT", isNullable: false),
        BoutiqueColumnSpec(
          name: "search_key",
          sqlType: "TEXT",
          generatedExpression: "lower(title)"
        ),
      ]
    }

    let table = try SyncedTable(schema: CanonicalNote.self)

    #expect(table.name == "canonical_notes")
    #expect(table.primaryKeyColumn == "uuid")
    #expect(table.columns == ["title"])
  }

  @Test func schemaSyncEnsuresColumns() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { await db.close() }
    try await db.execute(
      "CREATE TABLE columnItems (id TEXT PRIMARY KEY NOT NULL)"
    )

    enum ColumnItem: BoutiqueSchemaColumns {
      static var boutiqueTableName: String { "columnItems" }
      static var boutiqueCreateStatements: [String] {
        ["CREATE TABLE IF NOT EXISTS columnItems (id TEXT PRIMARY KEY NOT NULL)"]
      }
      static var boutiqueColumns: [BoutiqueColumnSpec] {
        [BoutiqueColumnSpec(name: "title", sqlType: "TEXT", defaultSQL: "''")]
      }
    }

    try await db.syncSchema([ColumnItem.self], policy: .additiveOnly)
    let exists = try await db.columnExists(table: "columnItems", name: "title")
    #expect(exists)
  }

  @Test func nestedBeginConcurrentThrows() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    // Without CDC, true MVCC concurrent begin is available on primary.
    let db = try await BoutiqueDB(
      url: url,
      startListening: false,
      enableCDC: false,
      concurrentWrites: true)
    defer { await db.close() }
    try await db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
    try await db.beginConcurrent()
    await #expect(throws: BoutiqueError.transactionInProgress) {
      try await db.beginConcurrent()
    }
    try await db.rollbackConcurrent()
  }

  @Test func capabilityProbeDoesNotEnableCDC() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try await BoutiqueDB(url: url, startListening: false, enableCDC: false)
    defer { await db.close() }

    #expect(!db.capabilities.cdc)
    #expect(
      try await db.unsafeConnection.queryOne(
        "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'turso_cdc'"
      ) == nil
    )
  }

  @Test func capabilityProbeReportsConfiguredMVCC() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try await BoutiqueDB(
      url: url,
      startListening: false,
      enableCDC: false,
      concurrentWrites: true
    )
    defer { await db.close() }

    #expect(db.capabilities.mvcc)
  }

  @Test func queryBoxSurfacesRefreshFailure() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let connection = try await TursoDatabase(url: url).connect(enableCDC: false)
    defer { await connection.close() }
    let store = try await TursoStore(connection: connection)
    enum Expected: Error { case failed }
    let box = TursoQueryBox(store: store, initial: 1) { throw Expected.failed }

    await box.forceRefresh()

    #expect(box.value == 1)
    #expect(box.fetchError?.contains("failed") == true)
  }

  @Test func dropTableIfExists() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { await db.close() }
    try await db.execute("CREATE TABLE doomed (id INTEGER PRIMARY KEY)")
    try await db.dropTableIfExists("doomed")
    let exists = try await db.tableExists("doomed")
    #expect(!exists)
  }

  @Test func vector32SparseRoundTrip() {
    let sparse = Vector32Sparse([0: 1.0, 3: 0.5])
    let again = Vector32Sparse(rawValue: sparse.rawValue)
    #expect(again?.entries[0] == 1.0)
    #expect(again?.entries[3] == 0.5)
  }

  @Test func liveQueryOneSetQuery() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { await db.close() }
    try await db.execute(
      """
      CREATE TABLE prNotes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    try await db.write { conn in
      try await conn.execute(
        "INSERT INTO prNotes (id, title) VALUES ('a','alpha'), ('b','beta')"
      )
    }
    let q = LiveQueryOne(db) {
      PRNote.where { $0.id.eq("a") }.asSelect()
    }
    await q.load()
    #expect(q.wrappedValue?.id == "a")
    q.setQuery {
      PRNote.where { $0.id.eq("b") }.asSelect()
    }
    let clock = ContinuousClock()
    let deadline = clock.now + .milliseconds(500)
    while clock.now < deadline {
      if q.wrappedValue?.id == "b" { break }
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(q.wrappedValue?.id == "b")
  }

  @Test func accountStatusNeedsAuthentication() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let conn = try await TursoDatabase(url: url).connect(enableCDC: true)
    defer { await conn.close() }
    try await conn.execute(
      "CREATE TABLE notes (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL)"
    )
    // Offline engine (no live CK container) — still exercises status mapping.
    let engine = try await TursoCKSyncEngine(
      connection: conn,
      configuration: TursoCKSyncConfiguration(
        syncedTables: [SyncedTable(name: "notes", columns: ["title"])],
        enablesCloudKit: false
      )
    )
    final class Box: @unchecked Sendable {
      var statuses: [SyncStatus] = []
    }
    let box = Box()
    await engine.setStatusSink { box.statuses.append($0) }
    try await engine.applyAccountStatus(.noAccount)
    #expect(box.statuses.contains(.needsAuthentication))

    // With CloudKit flag + inject, detect path also publishes.
    await engine.setInjectedAccountStatus(.restricted)
    // detect short-circuits when enablesCloudKit is false — call apply again.
    try await engine.applyAccountStatus(.restricted)
    #expect(box.statuses.filter { $0 == .needsAuthentication }.count >= 2)
  }

  @Test func isSynchronizingUsesLockedFlag() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let conn = try await TursoDatabase(url: url).connect(enableCDC: false)
    #expect(!(await conn.isApplyingRemoteChanges))
    await conn.withSynchronizingFlag { @Sendable in
      let applying1 = await conn.isApplyingRemoteChanges
      #expect(applying1)
      await conn.withSynchronizingFlag { @Sendable in
        let applying2 = await conn.isApplyingRemoteChanges
        #expect(applying2)
      }
      let applying3 = await conn.isApplyingRemoteChanges
      #expect(applying3)
    }
    #expect(!(await conn.isApplyingRemoteChanges))
  }

  @Test func asyncIOOpenAndWrite() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try await BoutiqueDB(
      url: url,
      startListening: false,
      openOptions: .tursoEnhancedAsync)
    defer { await db.close() }
    #expect(db.unsafeConnection.usesAsyncIO)
    try await db.execute(
      """
      CREATE TABLE asyncNotes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    try await db.write { conn in
      try await conn.execute(
        "INSERT INTO asyncNotes (id, title) VALUES (?, ?)",
        [.text("a1"), .text("async")]
      )
    }
    let rows = try await db.read { conn in
      try await conn.query("SELECT title FROM asyncNotes WHERE id = ?", [.text("a1")])
    }
    #expect(rows.first?["title"]?.stringValue == "async")
  }

  @Test func seamlessOpenPreservesEngineOptions() async throws {
    let url = tempURL()
    let db = try await BoutiqueDB.open(
      url: url,
      startListening: false,
      openOptions: .tursoEnhancedAsync)
    defer { await db.close() }
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: url)
    }
    #expect(db.unsafeConnection.usesAsyncIO)
  }
}
