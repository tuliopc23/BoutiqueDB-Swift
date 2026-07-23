import BoutiqueDB
import Foundation
import Testing
import TursoCKSync
import TursoKit

@Suite("CDC contracts")
@MainActor
struct CDCContractTests {
  @Test func writeConcurrentCapturesForDrain() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("cdc-conc-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try await BoutiqueDB(
      url: url,
      startListening: false,
      enableCDC: true,
      concurrentWrites: true)
    defer { await db.close() }
    try await db.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )

    try await db.writeConcurrent { conn in
      try await conn.execute(
        "INSERT INTO notes (id, title) VALUES (?, ?)",
        [.text("c1"), .text("from-concurrent")]
      )
    }

    let engine = try await TursoCKSyncEngine(
      connection: db.unsafeConnection,
      configuration: TursoCKSyncConfiguration(
        syncedTables: [SyncedTable(name: "notes", columns: ["title"])],
        enablesCloudKit: false
      )
    )
    try await engine.start(automaticallySync: false)
    let drained = try await engine.drainCDC()
    #expect(drained >= 1)
    let pending = await engine.pendingRecordZoneChanges
    #expect(!pending.isEmpty)
  }

  @Test func primaryWriteCapturesForDrain() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("cdc-prim-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try await BoutiqueDB(url: url, startListening: false, enableCDC: true)
    defer { await db.close() }
    try await db.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    try await db.write { conn in
      try await conn.execute(
        "INSERT INTO notes (id, title) VALUES (?, ?)",
        [.text("p1"), .text("primary")]
      )
    }

    let engine = try await TursoCKSyncEngine(
      connection: db.unsafeConnection,
      configuration: TursoCKSyncConfiguration(
        syncedTables: [SyncedTable(name: "notes", columns: ["title"])],
        enablesCloudKit: false
      )
    )
    try await engine.start(automaticallySync: false)
    let drained = try await engine.drainCDC()
    #expect(drained >= 1)
    let pending = await engine.pendingRecordZoneChanges
    #expect(!pending.isEmpty)
  }

  @Test func autoDrainOnLocalCommit() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("cdc-auto-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try await BoutiqueDB(url: url, startListening: false, enableCDC: true)
    defer { await db.close() }
    try await db.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )

    let sync = try await BoutiqueDBSyncEngine(
      db: db,
      syncedTables: [SyncedTable(name: "notes", columns: ["title"])],
      enablesCloudKit: false
    )
    try await sync.start(automaticallySync: false)
    sync.attach(to: db, automaticallyDrain: true)

    try await db.write { conn in
      try await conn.execute(
        "INSERT INTO notes (id, title) VALUES (?, ?)",
        [.text("a1"), .text("auto")]
      )
    }

    var pending = await sync.engine.pendingRecordZoneChanges
    var attempts = 0
    while pending.isEmpty && attempts < 20 {
      try await Task.sleep(for: .milliseconds(25))
      pending = await sync.engine.pendingRecordZoneChanges
      attempts += 1
    }
    #expect(!pending.isEmpty)
  }

  @Test func disablingAutoDrainRemovesCommitObserver() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("cdc-detach-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try await BoutiqueDB(url: url, startListening: false, enableCDC: true)
    defer { await db.close() }
    try await db.execute(
      "CREATE TABLE notes (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL)"
    )
    let sync = try await BoutiqueDBSyncEngine(
      db: db,
      syncedTables: [SyncedTable(name: "notes", columns: ["title"])],
      enablesCloudKit: false
    )
    try await sync.start(automaticallySync: false)
    sync.attach(to: db)
    sync.attach(to: db, automaticallyDrain: false)

    try await db.execute("INSERT INTO notes (id, title) VALUES ('detached', 'no drain')")

    let pending = await sync.engine.pendingRecordZoneChanges
    #expect(pending.isEmpty)
  }
}
