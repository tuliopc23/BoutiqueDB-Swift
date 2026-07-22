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

    let db = try BoutiqueDB(
      url: url,
      startListening: false,
      enableCDC: true,
      concurrentWrites: true)
    defer { db.close() }
    try await db.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )

    try await db.writeConcurrent { conn in
      try conn.execute(
        "INSERT INTO notes (id, title) VALUES (?, ?)",
        [.text("c1"), .text("from-concurrent")]
      )
    }

    let engine = try TursoCKSyncEngine(
      connection: db.unsafeConnection,
      configuration: TursoCKSyncConfiguration(
        syncedTables: [SyncedTable(name: "notes", columns: ["title"])],
        enablesCloudKit: false
      )
    )
    try engine.start(automaticallySync: false)
    let drained = try engine.drainCDC()
    #expect(drained >= 1)
    #expect(!engine.pendingRecordZoneChanges.isEmpty)
  }

  @Test func primaryWriteCapturesForDrain() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("cdc-prim-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try BoutiqueDB(url: url, startListening: false, enableCDC: true)
    defer { db.close() }
    try await db.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    try await db.write { conn in
      try conn.execute(
        "INSERT INTO notes (id, title) VALUES (?, ?)",
        [.text("p1"), .text("primary")]
      )
    }

    let engine = try TursoCKSyncEngine(
      connection: db.unsafeConnection,
      configuration: TursoCKSyncConfiguration(
        syncedTables: [SyncedTable(name: "notes", columns: ["title"])],
        enablesCloudKit: false
      )
    )
    try engine.start(automaticallySync: false)
    let drained = try engine.drainCDC()
    #expect(drained >= 1)
    #expect(!engine.pendingRecordZoneChanges.isEmpty)
  }

  @Test func autoDrainOnLocalCommit() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("cdc-auto-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try BoutiqueDB(url: url, startListening: false, enableCDC: true)
    defer { db.close() }
    try await db.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )

    let sync = try BoutiqueDBSyncEngine(
      db: db,
      syncedTables: [SyncedTable(name: "notes", columns: ["title"])],
      enablesCloudKit: false
    )
    try sync.start(automaticallySync: false)
    sync.attach(to: db, automaticallyDrain: true)

    try await db.write { conn in
      try conn.execute(
        "INSERT INTO notes (id, title) VALUES (?, ?)",
        [.text("a1"), .text("auto")]
      )
    }

    #expect(!sync.engine.pendingRecordZoneChanges.isEmpty)
  }
}
