import CloudKit
import Foundation
import Testing
import TursoCKSync
import TursoKit
import TursoObservation

@Suite("TursoCKSync bridge")
struct TursoCKSyncTests {
  private func makeConnection() throws -> (URL, TursoConnection) {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-ck-\(UUID().uuidString).db")
    let conn = try TursoDatabase(url: url).connect(enableCDC: true)
    try conn.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
      """
    )
    return (url, conn)
  }

  private var notesTable: SyncedTable {
    SyncedTable(name: "notes", columns: ["title", "body", "updatedAt"])
  }

  private var syncConfiguration: TursoCKSyncConfiguration {
    TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      enablesCloudKit: false
    )
  }

  @Test func metadataAndStatePersistence() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }

    let meta = SyncMetadataStore(connection: conn)
    try meta.migrate()
    #expect(try meta.loadCDCCursor() == 0)
    #expect(try meta.loadStateSerialization() == nil)

    try meta.saveCDCCursor(42)
    #expect(try meta.loadCDCCursor() == 42)

    try meta.upsertRecordMeta(
      table: "notes",
      rowPK: "abc",
      recordName: "notes:abc",
      zoneName: "app.default",
      systemFields: Data([1, 2, 3])
    )
    #expect(try meta.systemFields(table: "notes", rowPK: "abc") == Data([1, 2, 3]))
  }

  @Test func outboundCDCDrainBuildsPendingChanges() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }

    let bridge = try TursoCKSyncEngine(
      connection: conn,
      configuration: syncConfiguration
    )
    try bridge.start(automaticallySync: false)

    let id = UUID().uuidString
    try conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
      [.text(id), .text("T"), .text("B"), .text("2026-01-01T00:00:00Z")]
    )
    let rawCDC = try conn.query(
      "SELECT change_id, change_type, table_name, id FROM turso_cdc WHERE change_type != 2"
    )
    #expect(!rawCDC.isEmpty)

    let drained = try bridge.drainCDC()
    #expect(drained >= 1)

    let pending = bridge.pendingRecordZoneChanges
    let names: [String] = pending.compactMap { change in
      switch change {
      case .saveRecord(let recordID), .deleteRecord(let recordID):
        return recordID.recordName
      @unknown default:
        return nil
      }
    }
    #expect(names.contains("notes:\(id)"))

    let record = try bridge.makeRecord(
      for: CKRecord.ID(recordName: "notes:\(id)", zoneID: bridge.zoneID)
    )
    #expect(record?["title"] as? String == "T")
    #expect(try bridge.metadata.loadCDCCursor() > 0)
  }

  @Test func inboundApplyAndEchoSuppression() throws {
    let (urlA, connA) = try makeConnection()
    let (urlB, connB) = try makeConnection()
    defer {
      try? FileManager.default.removeItem(at: urlA)
      try? FileManager.default.removeItem(at: urlB)
    }

    let deviceA = try TursoCKSyncEngine(
      connection: connA,
      configuration: syncConfiguration
    )
    try deviceA.start(automaticallySync: false)

    let deviceB = try TursoCKSyncEngine(
      connection: connB,
      configuration: syncConfiguration
    )
    try deviceB.start(automaticallySync: false)

    let id = UUID().uuidString
    try deviceA.performLocalWrite {
      try connA.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text(id), .text("From A"), .text("body"), .text("2026-01-01T00:00:00Z")]
      )
    }

    let record = try #require(
      try deviceA.makeRecord(
        for: CKRecord.ID(recordName: "notes:\(id)", zoneID: deviceA.zoneID)
      )
    )

    // Simulate CloudKit → device B
    try deviceB.applyRemoteRecord(record)

    let row = try connB.queryOne("SELECT title FROM notes WHERE id = ?", [.text(id)])
    #expect(row?["title"]?.stringValue == "From A")

    // Echo must not enqueue outbound pending for the inbound apply.
    let pendingB = deviceB.pendingRecordZoneChanges
    let echoed = pendingB.contains {
      if case .saveRecord(let rid) = $0 { return rid.recordName == "notes:\(id)" }
      return false
    }
    #expect(!echoed)

    // Delete path
    try deviceB.applyRemoteDeletion(
      recordID: CKRecord.ID(recordName: "notes:\(id)", zoneID: deviceB.zoneID)
    )
    #expect(try connB.queryOne("SELECT id FROM notes WHERE id = ?", [.text(id)]) == nil)
  }

  @Test func systemFieldsRoundTrip() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }

    let bridge = try TursoCKSyncEngine(
      connection: conn,
      configuration: syncConfiguration
    )
    try bridge.start(automaticallySync: false)

    let id = UUID().uuidString
    let recordID = CKRecord.ID(recordName: "notes:\(id)", zoneID: bridge.zoneID)
    let record = CKRecord(recordType: "notes", recordID: recordID)
    record["title"] = "X"
    record["body"] = "Y"
    record["updatedAt"] = "2026-01-01T00:00:00Z"
    record["id"] = id

    try bridge.applyRemoteRecord(record)
    let fields = try bridge.metadata.systemFields(table: "notes", rowPK: id)
    #expect(fields != nil)

    // Local update then rebuild record should hydrate system fields.
    try bridge.performLocalWrite {
      try conn.execute(
        "UPDATE notes SET title = ? WHERE id = ?",
        [.text("X2"), .text(id)]
      )
    }
    let rebuilt = try #require(try bridge.makeRecord(for: recordID))
    #expect(rebuilt["title"] as? String == "X2")
  }

  @Test func accountWipeRebootstrap() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }

    let bridge = try TursoCKSyncEngine(
      connection: conn,
      configuration: syncConfiguration
    )
    try bridge.start(automaticallySync: false)

    try bridge.performLocalWrite {
      try conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text("1"), .text("t"), .text("b"), .text("2026-01-01T00:00:00Z")]
      )
    }
    #expect(try conn.query("SELECT * FROM notes").count == 1)

    try bridge.wipeAndRebootstrap()
    #expect(try conn.query("SELECT * FROM notes").isEmpty)
    #expect(try bridge.metadata.loadCDCCursor() == 0)
    #expect(try bridge.metadata.loadStateSerialization() == nil)
  }

  @MainActor
  @Test func observationInvalidatesOnCDC() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }

    try conn.enableCaptureDataChanges(mode: .full)

    let store = TursoStore(connection: conn)
    let before = store.generation

    try conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
      [.text("obs"), .text("t"), .text("b"), .text("2026-01-01T00:00:00Z")]
    )
    store.poll()
    #expect(store.generation == before + 1)
  }

  /// Local stand-in for a two-device CloudKit round-trip (A → record → B).
  /// Full simulator CloudKit requires entitlements + iCloud account.
  @Test func simulatedTwoDeviceRoundTrip() throws {
    let (urlA, connA) = try makeConnection()
    let (urlB, connB) = try makeConnection()
    defer {
      try? FileManager.default.removeItem(at: urlA)
      try? FileManager.default.removeItem(at: urlB)
    }

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      conflictPolicy: .serverWins,
      enablesCloudKit: false
    )
    let a = try TursoCKSyncEngine(connection: connA, configuration: config)
    let b = try TursoCKSyncEngine(connection: connB, configuration: config)
    try a.start(automaticallySync: false)
    try b.start(automaticallySync: false)

    let id = UUID().uuidString
    try a.performLocalWrite {
      try connA.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text(id), .text("sync-me"), .text("payload"), .text("2026-07-21T00:00:00Z")]
      )
    }
    let outbound = try #require(
      try a.makeRecord(for: CKRecord.ID(recordName: "notes:\(id)", zoneID: a.zoneID))
    )
    try b.applyRemoteRecord(outbound)

    #expect(
      try connB.queryOne("SELECT title, body FROM notes WHERE id = ?", [.text(id)])?["title"]?
        .stringValue == "sync-me"
    )

    try a.performLocalWrite {
      try connA.execute("DELETE FROM notes WHERE id = ?", [.text(id)])
    }
    try b.applyRemoteDeletion(recordID: CKRecord.ID(recordName: "notes:\(id)", zoneID: b.zoneID))
    #expect(try connB.query("SELECT * FROM notes WHERE id = ?", [.text(id)]).isEmpty)
  }
}
