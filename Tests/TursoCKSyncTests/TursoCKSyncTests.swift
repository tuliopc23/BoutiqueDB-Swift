import CloudKit
import Foundation
import Testing
import TursoKit
import TursoObservation

@testable import TursoCKSync

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
    defer { conn.close() }

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
    defer { conn.close() }

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
      connB.close()
      connA.close()
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
    defer { conn.close() }

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
    defer { conn.close() }

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
    defer { conn.close() }

    try conn.enableCaptureDataChanges(mode: .full)

    let store = TursoStore(connection: conn)
    let before = store.generation

    try conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
      [.text("obs"), .text("t"), .text("b"), .text("2026-01-01T00:00:00Z")]
    )
    store.advanceFromCDC()
    #expect(store.generation == before + 1)
  }

  /// Local stand-in for a two-device CloudKit round-trip (A → record → B).
  /// Full simulator CloudKit requires entitlements + iCloud account.
  @Test func simulatedTwoDeviceRoundTrip() throws {
    let (urlA, connA) = try makeConnection()
    let (urlB, connB) = try makeConnection()
    defer {
      connB.close()
      connA.close()
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

  @Test func multiTableSyncRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-ck-multi-\(UUID().uuidString).db")
    let conn = try TursoDatabase(url: url).connect(enableCDC: true)
    defer { try? FileManager.default.removeItem(at: url) }

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
    try conn.execute(
      """
      CREATE TABLE tags (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
      """
    )

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [
        notesTable,
        SyncedTable(name: "tags", columns: ["name", "updatedAt"]),
      ],
      enablesCloudKit: false
    )
    let engine = try TursoCKSyncEngine(connection: conn, configuration: config)
    try engine.start(automaticallySync: false)

    try engine.performLocalWrite {
      try conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES ('n1','t','b','2026-01-01T00:00:00Z')"
      )
      try conn.execute(
        "INSERT INTO tags (id, name, updatedAt) VALUES ('t1','swift','2026-01-01T00:00:00Z')"
      )
    }

    let pendingNames = engine.pendingRecordZoneChanges.compactMap { change -> String? in
      if case .saveRecord(let id) = change { return id.recordName }
      return nil
    }
    #expect(pendingNames.contains("notes:n1"))
    #expect(pendingNames.contains("tags:t1"))
  }

  @Test func pendingBatchesRespectMaxBatchSize() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      maxBatchSize: 250,
      drainCDCLimit: 500,
      enablesCloudKit: false
    )
    let engine = try TursoCKSyncEngine(connection: conn, configuration: config)
    try engine.start(automaticallySync: false)

    try engine.performLocalWrite {
      for i in 0..<600 {
        try conn.execute(
          "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
          [
            .text("id-\(i)"),
            .text("t"),
            .text("b"),
            .text("2026-01-01T00:00:00Z"),
          ]
        )
      }
    }

    let batches = engine.pendingBatches()
    #expect(!batches.isEmpty)
    #expect(batches.allSatisfy { $0.count <= 250 })
    let total = batches.reduce(0) { $0 + $1.count }
    // drainCDCLimit 500 — some CDC rows may be commit markers filtered out.
    #expect(total >= 400)
    #expect(total <= 600)
    #expect(batches.count >= 2)  // 400+ pending at size 250 ⇒ multiple batches
  }

  @Test func lastWriterWinsConflict() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      conflictPolicy: .lastWriterWins(field: "updatedAt"),
      enablesCloudKit: false
    )
    let engine = try TursoCKSyncEngine(connection: conn, configuration: config)
    try engine.start(automaticallySync: false)

    let id = "lw1"
    try engine.performLocalWrite {
      try conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text(id), .text("local"), .text("b"), .text("2026-07-22T10:05:00Z")]
      )
    }

    let recordID = CKRecord.ID(recordName: "notes:\(id)", zoneID: engine.zoneID)
    let server = CKRecord(recordType: "notes", recordID: recordID)
    server["id"] = id
    server["title"] = "server"
    server["body"] = "b"
    server["updatedAt"] = "2026-07-22T10:00:00Z"

    let failed = try #require(try engine.makeRecord(for: recordID))
    try engine.resolveConflictForTesting(failedRecord: failed, serverRecord: server)

    // Local is newer → keep local title, re-pend save.
    let title = try conn.queryOne("SELECT title FROM notes WHERE id = ?", [.text(id)])?[
      "title"
    ]?.stringValue
    #expect(title == "local")
    let pending = engine.pendingRecordZoneChanges.contains {
      if case .saveRecord(let rid) = $0 { return rid.recordName == "notes:\(id)" }
      return false
    }
    #expect(pending)
  }

  @Test func serverWinsConflict() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      conflictPolicy: .serverWins,
      enablesCloudKit: false
    )
    let engine = try TursoCKSyncEngine(connection: conn, configuration: config)
    try engine.start(automaticallySync: false)

    let id = "sw1"
    try engine.performLocalWrite {
      try conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text(id), .text("local"), .text("b"), .text("2026-07-22T10:05:00Z")]
      )
    }

    let recordID = CKRecord.ID(recordName: "notes:\(id)", zoneID: engine.zoneID)
    let server = CKRecord(recordType: "notes", recordID: recordID)
    server["id"] = id
    server["title"] = "server"
    server["body"] = "b"
    server["updatedAt"] = "2026-07-22T10:00:00Z"

    let failed = try #require(try engine.makeRecord(for: recordID))
    try engine.resolveConflictForTesting(failedRecord: failed, serverRecord: server)

    let title = try conn.queryOne("SELECT title FROM notes WHERE id = ?", [.text(id)])?[
      "title"
    ]?.stringValue
    #expect(title == "server")
  }

  @Test func clientWinsPreservesLocalPayloadForRetry() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }
    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      conflictPolicy: .clientWins,
      enablesCloudKit: false
    )
    let engine = try TursoCKSyncEngine(connection: conn, configuration: config)
    try engine.start(automaticallySync: false)
    try engine.performLocalWrite {
      try conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES ('cw1','local','b','2026-07-22T10:05:00Z')"
      )
    }

    let recordID = CKRecord.ID(recordName: "notes:cw1", zoneID: engine.zoneID)
    let failed = try #require(try engine.makeRecord(for: recordID))
    let server = CKRecord(recordType: "notes", recordID: recordID)
    server["id"] = "cw1"
    server["title"] = "server"
    server["body"] = "b"
    server["updatedAt"] = "2026-07-22T10:00:00Z"

    try engine.resolveConflictForTesting(failedRecord: failed, serverRecord: server)

    let outbound = try #require(try engine.makeRecord(for: recordID))
    #expect(outbound["title"] as? String == "local")
    #expect(
      try conn.queryOne("SELECT title FROM notes WHERE id = 'cw1'")?["title"]?.stringValue
        == "local")
    #expect(
      engine.pendingRecordZoneChanges.contains { change in
        if case .saveRecord(let id) = change { return id == recordID }
        return false
      })
  }

  @Test func pendingChangesSurviveEngineRestart() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }
    let first = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try first.start(automaticallySync: false)
    try conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES ('restart','local','b','2026-01-01T00:00:00Z')"
    )
    _ = try first.drainCDC()
    let cursor = try first.metadata.loadCDCCursor()
    first.stop()

    let restarted = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try restarted.start(automaticallySync: false)
    #expect(try restarted.metadata.loadCDCCursor() == cursor)
    #expect(
      restarted.pendingRecordZoneChanges.contains { change in
        if case .saveRecord(let id) = change { return id.recordName == "notes:restart" }
        return false
      })
  }

  @Test func acknowledgedPendingChangeDoesNotReturnAfterRestart() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }
    let first = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try first.start(automaticallySync: false)
    try conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES ('acked','local','b','2026-01-01T00:00:00Z')"
    )
    _ = try first.drainCDC()
    let recordID = CKRecord.ID(recordName: "notes:acked", zoneID: first.zoneID)
    try first.acknowledgePendingChangeForTesting(recordID: recordID)
    first.stop()

    let restarted = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try restarted.start(automaticallySync: false)
    #expect(
      !restarted.pendingRecordZoneChanges.contains { change in
        if case .saveRecord(let id) = change { return id == recordID }
        return false
      })
  }

  @Test func missingProviderRowRemovesDurableSave() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }
    let first = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try first.start(automaticallySync: false)
    try conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES ('missing','local','b','2026-01-01T00:00:00Z')"
    )
    _ = try first.drainCDC()
    let recordID = CKRecord.ID(recordName: "notes:missing", zoneID: first.zoneID)
    try conn.execute("DELETE FROM notes WHERE id = 'missing'")

    #expect(try first.recordForPendingSaveForTesting(recordID: recordID) == nil)
    first.stop()
    let restarted = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try restarted.start(automaticallySync: false)
    #expect(
      !restarted.pendingRecordZoneChanges.contains { change in
        if case .saveRecord(let id) = change { return id == recordID }
        return false
      })
  }

  @Test func invalidRecordNameDoesNotAdvanceCursor() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }
    let engine = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try engine.start(automaticallySync: false)
    let oversizedID = String(repeating: "x", count: 300)
    try conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, 't', 'b', '2026-01-01T00:00:00Z')",
      [.text(oversizedID)]
    )

    #expect(throws: TursoCKSyncError.self) {
      _ = try engine.drainCDC()
    }
    #expect(try engine.metadata.loadCDCCursor() == 0)
    #expect(engine.pendingRecordZoneChanges.isEmpty)
  }

  @Test func cloudKitRequiresExplicitContainer() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }
    let config = TursoCKSyncConfiguration(
      syncedTables: [notesTable],
      enablesCloudKit: true
    )
    #expect(throws: TursoCKSyncError.missingCloudKitContainer) {
      _ = try TursoCKSyncEngine(connection: conn, configuration: config)
    }
  }

  @Test func syncConfigurationRejectsReservedFieldsAndUniqueIndexes() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }
    let reserved = TursoCKSyncConfiguration(
      syncedTables: [SyncedTable(name: "notes", columns: ["recordID"])],
      enablesCloudKit: false
    )
    #expect(throws: TursoCKSyncError.self) {
      _ = try TursoCKSyncEngine(connection: conn, configuration: reserved)
    }

    try conn.execute("CREATE UNIQUE INDEX notes_title_unique ON notes(title)")
    #expect(
      throws: TursoCKSyncError.uniqueConstraintUnsupported(
        table: "notes",
        index: "notes_title_unique"
      )
    ) {
      _ = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    }
  }

  @Test func inboundEchoSuppressionPreservesInterleavedLocalChange() throws {
    let (url, primary) = try makeConnection()
    defer { primary.close() }
    defer { try? FileManager.default.removeItem(at: url) }
    let secondDatabase = TursoDatabase(url: url)
    let writer = try secondDatabase.connect(enableCDC: true)
    let engine = try TursoCKSyncEngine(connection: primary, configuration: syncConfiguration)
    try engine.start(automaticallySync: false)

    try writer.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES ('local-interleaved','local','b','2026-01-01T00:00:00Z')"
    )
    let remoteID = CKRecord.ID(recordName: "notes:remote", zoneID: engine.zoneID)
    let remote = CKRecord(recordType: "notes", recordID: remoteID)
    remote["id"] = "remote"
    remote["title"] = "remote"
    remote["body"] = "b"
    remote["updatedAt"] = "2026-01-01T00:00:00Z"
    try engine.applyRemoteRecord(remote)

    #expect(
      engine.pendingRecordZoneChanges.contains { change in
        if case .saveRecord(let id) = change { return id.recordName == "notes:local-interleaved" }
        return false
      })
  }

  @Test func removingSyncedColumnRequiresExplicitReset() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }
    _ = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    let changed = TursoCKSyncConfiguration(
      syncedTables: [SyncedTable(name: "notes", columns: ["title", "updatedAt"])],
      enablesCloudKit: false
    )
    #expect(throws: TursoCKSyncError.self) {
      _ = try TursoCKSyncEngine(connection: conn, configuration: changed)
    }
  }

  @Test func accountHashChangePreservesLocalData() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let engine = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try engine.start(automaticallySync: false)
    try engine.noteAccountIdentity("account-a")

    try engine.performLocalWrite {
      try conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES ('1','t','b','2026-01-01T00:00:00Z')"
      )
    }
    #expect(try conn.query("SELECT * FROM notes").count == 1)

    try engine.noteAccountIdentity("account-b")
    // Local user data preserved; metadata wiped and rows re-enqueued.
    #expect(try conn.query("SELECT * FROM notes").count == 1)
    #expect(try engine.metadata.loadAccountHash() == "account-b")
  }

  @Test func cloudKitSyncAdapterStatusStream() async throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let adapter = try CloudKitSyncAdapter(
      connection: conn,
      configuration: syncConfiguration
    )
    var iterator = adapter.syncStatus().makeAsyncIterator()
    let first = await iterator.next()
    #expect(first == .idle)

    try await adapter.start()
    _ = try await adapter.drainLocalChanges()
  }

  @Test func transportNeutralRemoteRecordRoundTrip() async throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let engine = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try engine.start(automaticallySync: false)
    let adapter = CloudKitSyncAdapter(engine: engine)
    let id = UUID().uuidString
    try await adapter.applyRemoteChanges([
      .upsert(
        RemoteRecord(
          recordName: "notes:\(id)",
          recordType: "notes",
          fields: [
            "id": .string(id),
            "title": .string("Neutral"),
            "body": .string("payload"),
            "updatedAt": .string("2026-07-22T00:00:00Z"),
          ]
        )
      )
    ])

    #expect(
      try conn.queryOne("SELECT title FROM notes WHERE id = ?", [.text(id)])?["title"]?
        .stringValue == "Neutral"
    )
    try await adapter.fetchChanges()
    try await adapter.sendChanges()
    try await adapter.syncChanges()

    try await adapter.applyRemoteChanges([.delete(recordName: "notes:\(id)")])
    #expect(try conn.queryOne("SELECT id FROM notes WHERE id = ?", [.text(id)]) == nil)
  }

  @Test func unreadableCloudKitAssetIsExplicitFailure() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let engine = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try engine.start(automaticallySync: false)
    let id = UUID().uuidString
    let record = CKRecord(
      recordType: "notes",
      recordID: CKRecord.ID(recordName: "notes:\(id)", zoneID: engine.zoneID)
    )
    record["title"] = CKAsset(
      fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-asset-\(UUID().uuidString)")
    )
    record["body"] = "body"
    record["updatedAt"] = "2026-07-22T00:00:00Z"

    #expect(throws: TursoCKSyncError.self) {
      try engine.applyRemoteRecord(record)
    }
  }

  @Test func invalidTransportMetadataIsExplicitFailure() async throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let engine = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try engine.start(automaticallySync: false)
    let adapter = CloudKitSyncAdapter(engine: engine)

    await #expect(throws: TursoCKSyncError.self) {
      try await adapter.applyRemoteChanges([
        .upsert(
          RemoteRecord(
            recordName: "notes:invalid-metadata",
            recordType: "notes",
            fields: [:],
            transportMetadata: Data("not-an-archive".utf8)
          )
        )
      ])
    }
  }

  @Test func wipePreservingDataReenqueues() throws {
    let (url, conn) = try makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { conn.close() }

    let engine = try TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try engine.start(automaticallySync: false)
    try engine.performLocalWrite {
      try conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES ('1','t','b','2026-01-01T00:00:00Z')"
      )
    }
    try engine.wipeAndRebootstrap(preserveLocalUserData: true)
    #expect(try conn.query("SELECT * FROM notes").count == 1)
    #expect(!engine.pendingRecordZoneChanges.isEmpty)
  }
}
