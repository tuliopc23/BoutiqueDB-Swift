import BoutiqueDB
import Foundation
import StructuredQueries
import StructuredQueriesTurso
import Testing
import TursoCKSync
import TursoKit

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
    let db = try BoutiqueDB(url: url, startListening: false)
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
    let db = try BoutiqueDB(url: url, startListening: false)
    try await db.execute(
      """
      CREATE TABLE prNotes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    try await db.write { conn in
      try conn.execute(
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
      BoutiqueMigration("v1") { db in
        try await db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
      }
    }
    let db = try await BoutiqueDB.open(url: url, startListening: false, migrations: plan)
    let done = try await BoutiqueMigrator().hasCompletedMigrations(on: db, plan: plan)
    #expect(done)
  }

  @Test func schemaSyncEnsuresColumns() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try BoutiqueDB(url: url, startListening: false)
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
    let db = try BoutiqueDB(
      url: url,
      startListening: false,
      enableCDC: false,
      concurrentWrites: true
    )
    try await db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
    try await db.beginConcurrent()
    await #expect(throws: BoutiqueError.transactionInProgress) {
      try await db.beginConcurrent()
    }
    try await db.rollbackConcurrent()
  }

  @Test func dropTableIfExists() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try BoutiqueDB(url: url, startListening: false)
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
    let db = try BoutiqueDB(url: url, startListening: false)
    try await db.execute(
      """
      CREATE TABLE prNotes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    try await db.write { conn in
      try conn.execute(
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
    let conn = try TursoDatabase(url: url).connect(enableCDC: true)
    // Offline engine (no live CK container) — still exercises status mapping.
    let engine = try TursoCKSyncEngine(
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
    engine.statusSink = { box.statuses.append($0) }
    try engine.applyAccountStatus(.noAccount)
    #expect(box.statuses.contains(.needsAuthentication))

    // With CloudKit flag + inject, detect path also publishes.
    engine.injectedAccountStatus = .restricted
    // detect short-circuits when enablesCloudKit is false — call apply again.
    try engine.applyAccountStatus(.restricted)
    #expect(box.statuses.filter { $0 == .needsAuthentication }.count >= 2)
  }

  @Test func isSynchronizingUsesLockedFlag() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let conn = try TursoDatabase(url: url).connect(enableCDC: false)
    #expect(!conn.isApplyingRemoteChanges)
    try conn.withSynchronizingFlag {
      #expect(conn.isApplyingRemoteChanges)
    }
    #expect(!conn.isApplyingRemoteChanges)
  }

  @Test func asyncIOOpenAndWrite() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try BoutiqueDB(
      url: url,
      startListening: false,
      openOptions: .tursoEnhancedAsync
    )
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
      try conn.execute(
        "INSERT INTO asyncNotes (id, title) VALUES (?, ?)",
        [.text("a1"), .text("async")]
      )
    }
    let rows = try await db.read { conn in
      try conn.query("SELECT title FROM asyncNotes WHERE id = ?", [.text("a1")])
    }
    #expect(rows.first?["title"]?.stringValue == "async")
  }
}
