import CloudKit
import Foundation
import Testing
import TursoKit
import TursoObservation

@testable import TursoCKSync

@Suite("TursoCKSync bridge")
struct TursoCKSyncTests {
  private func makeConnection() async throws -> (URL, TursoConnection) {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-ck-\(UUID().uuidString).db")
    let conn = try await TursoDatabase(url: url).connect(enableCDC: true)
    try await conn.execute(
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

  @Test func metadataAndStatePersistence() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let meta = SyncMetadataStore(connection: conn)
    try await meta.migrate()
    #expect(try await meta.loadCDCCursor() == 0)
    #expect(try await meta.loadStateSerialization() == nil)

    try await meta.saveCDCCursor(42)
    #expect(try await meta.loadCDCCursor() == 42)

    try await meta.upsertRecordMeta(
      table: "notes",
      rowPK: "abc",
      recordName: "notes:abc",
      zoneName: "app.default",
      systemFields: Data([1, 2, 3])
    )
    #expect(try await meta.systemFields(table: "notes", rowPK: "abc") == Data([1, 2, 3]))
  }

  @Test func outboundCDCDrainBuildsPendingChanges() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let bridge = try await TursoCKSyncEngine(
      connection: conn,
      configuration: syncConfiguration
    )
    try await bridge.start(automaticallySync: false)

    let id = UUID().uuidString
    try await conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
      [.text(id), .text("T"), .text("B"), .text("2026-01-01T00:00:00Z")]
    )
    let rawCDC = try await conn.query(
      "SELECT change_id, change_type, table_name, id FROM turso_cdc WHERE change_type != 2"
    )
    #expect(!rawCDC.isEmpty)

    let drained = try await bridge.drainCDC()
    #expect(drained >= 1)

    let pending = await bridge.pendingRecordZoneChanges
    let names: [String] = pending.compactMap { change in
      switch change {
      case .saveRecord(let recordID), .deleteRecord(let recordID):
        return recordID.recordName
      @unknown default:
        return nil
      }
    }
    #expect(names.contains("notes:\(id)"))

    let record = try #require(
      try await bridge.makeRecord(
        for: CKRecord.ID(recordName: "notes:\(id)", zoneID: bridge.zoneID)
      )
    )
    #expect(record["title"] as? String == "T")
    #expect(try await bridge.metadata.loadCDCCursor() > 0)
  }

  @Test func inboundApplyAndEchoSuppression() async throws {
    let (urlA, connA) = try await makeConnection()
    let (urlB, connB) = try await makeConnection()
    defer {
      await connB.close()
      await connA.close()
      try? FileManager.default.removeItem(at: urlA)
      try? FileManager.default.removeItem(at: urlB)
    }

    let deviceA = try await TursoCKSyncEngine(
      connection: connA,
      configuration: syncConfiguration
    )
    try await deviceA.start(automaticallySync: false)

    let deviceB = try await TursoCKSyncEngine(
      connection: connB,
      configuration: syncConfiguration
    )
    try await deviceB.start(automaticallySync: false)

    let id = UUID().uuidString
    try await deviceA.performLocalWrite {
      try await connA.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text(id), .text("From A"), .text("body"), .text("2026-01-01T00:00:00Z")]
      )
    }

    let record = try #require(
      try await deviceA.makeRecord(
        for: CKRecord.ID(recordName: "notes:\(id)", zoneID: deviceA.zoneID)
      )
    )

    // Simulate CloudKit → device B
    try await deviceB.applyRemoteRecord(record)

    let row = try await connB.queryOne("SELECT title FROM notes WHERE id = ?", [.text(id)])
    #expect(row?["title"]?.stringValue == "From A")

    // Echo must not enqueue outbound pending for the inbound apply.
    let pendingB = await deviceB.pendingRecordZoneChanges
    let echoed = pendingB.contains {
      if case .saveRecord(let rid) = $0 { return rid.recordName == "notes:\(id)" }
      return false
    }
    #expect(!echoed)

    // Delete path
    try await deviceB.applyRemoteDeletion(
      recordID: CKRecord.ID(recordName: "notes:\(id)", zoneID: deviceB.zoneID)
    )
    #expect(try await connB.queryOne("SELECT id FROM notes WHERE id = ?", [.text(id)]) == nil)
  }

  @Test func systemFieldsRoundTrip() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let bridge = try await TursoCKSyncEngine(
      connection: conn,
      configuration: syncConfiguration
    )
    try await bridge.start(automaticallySync: false)

    let id = UUID().uuidString
    let recordID = CKRecord.ID(recordName: "notes:\(id)", zoneID: bridge.zoneID)
    let record = CKRecord(recordType: "notes", recordID: recordID)
    record["title"] = "X"
    record["body"] = "Y"
    record["updatedAt"] = "2026-01-01T00:00:00Z"
    record["id"] = id

    try await bridge.applyRemoteRecord(record)
    let fields = try await bridge.metadata.systemFields(table: "notes", rowPK: id)
    #expect(fields != nil)

    // Local update then rebuild record should hydrate system fields.
    try await bridge.performLocalWrite {
      try await conn.execute(
        "UPDATE notes SET title = ? WHERE id = ?",
        [.text("X2"), .text(id)]
      )
    }
    let rebuilt = try #require(try await bridge.makeRecord(for: recordID))
    #expect(rebuilt["title"] as? String == "X2")
  }

  @Test func accountWipeRebootstrap() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let bridge = try await TursoCKSyncEngine(
      connection: conn,
      configuration: syncConfiguration
    )
    try await bridge.start(automaticallySync: false)

    try await bridge.performLocalWrite {
      try await conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text("1"), .text("t"), .text("b"), .text("2026-01-01T00:00:00Z")]
      )
    }
    #expect(try await conn.query("SELECT * FROM notes").count == 1)

    try await bridge.wipeAndRebootstrap()
    #expect(try await conn.query("SELECT * FROM notes").isEmpty)
    #expect(try await bridge.metadata.loadCDCCursor() == 0)
    #expect(try await bridge.metadata.loadStateSerialization() == nil)
  }

  @MainActor
  @Test func observationInvalidatesOnCDC() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    try await conn.enableCaptureDataChanges(mode: .full)

    let store = try await TursoStore(connection: conn)
    let before = store.generation

    try await conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
      [.text("obs"), .text("t"), .text("b"), .text("2026-01-01T00:00:00Z")]
    )
    await store.advanceFromCDC()
    #expect(store.generation == before + 1)
  }

  /// Local stand-in for a two-device CloudKit round-trip (A → record → B).
  /// Full simulator CloudKit requires entitlements + iCloud account.
  @Test func simulatedTwoDeviceRoundTrip() async throws {
    let (urlA, connA) = try await makeConnection()
    let (urlB, connB) = try await makeConnection()
    defer {
      await connB.close()
      await connA.close()
      try? FileManager.default.removeItem(at: urlA)
      try? FileManager.default.removeItem(at: urlB)
    }

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      conflictPolicy: .serverWins,
      enablesCloudKit: false
    )
    let a = try await TursoCKSyncEngine(connection: connA, configuration: config)
    let b = try await TursoCKSyncEngine(connection: connB, configuration: config)
    try await a.start(automaticallySync: false)
    try await b.start(automaticallySync: false)

    let id = UUID().uuidString
    try await a.performLocalWrite {
      try await connA.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, ?, ?, ?)",
        [.text(id), .text("sync-me"), .text("payload"), .text("2026-07-21T00:00:00Z")]
      )
    }
    let outbound = try #require(
      try await a.makeRecord(for: CKRecord.ID(recordName: "notes:\(id)", zoneID: a.zoneID))
    )
    try await b.applyRemoteRecord(outbound)

    #expect(
      try await connB.queryOne("SELECT title, body FROM notes WHERE id = ?", [.text(id)])?["title"]?
        .stringValue == "sync-me"
    )

    try await a.performLocalWrite {
      try await connA.execute("DELETE FROM notes WHERE id = ?", [.text(id)])
    }
    try await b.applyRemoteDeletion(recordID: CKRecord.ID(recordName: "notes:\(id)", zoneID: b.zoneID))
    #expect(try await connB.query("SELECT * FROM notes WHERE id = ?", [.text(id)]).isEmpty)
  }

  @Test func multiTableSyncRoundTrip() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-ck-multi-\(UUID().uuidString).db")
    let conn = try await TursoDatabase(url: url).connect(enableCDC: true)
    defer {
      try? FileManager.default.removeItem(at: url)
      await conn.close()
    }

    try await conn.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
      """
    )
    try await conn.execute(
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
    let engine = try await TursoCKSyncEngine(connection: conn, configuration: config)
    try await engine.start(automaticallySync: false)

    try await engine.performLocalWrite {
      try await conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES ('n1','t','b','2026-01-01T00:00:00Z')"
      )
      try await conn.execute(
        "INSERT INTO tags (id, name, updatedAt) VALUES ('t1','swift','2026-01-01T00:00:00Z')"
      )
    }

    let pending = await engine.pendingRecordZoneChanges
    let pendingNames = pending.compactMap { change -> String? in
      if case .saveRecord(let id) = change { return id.recordName }
      return nil
    }
    #expect(pendingNames.contains("notes:n1"))
    #expect(pendingNames.contains("tags:t1"))
  }

  @Test func pendingBatchesRespectMaxBatchSize() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      maxBatchSize: 250,
      drainCDCLimit: 500,
      enablesCloudKit: false
    )
    let engine = try await TursoCKSyncEngine(connection: conn, configuration: config)
    try await engine.start(automaticallySync: false)

    try await engine.performLocalWrite {
      for i in 0..<600 {
        try await conn.execute(
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

    let batches = await engine.pendingBatches()
    #expect(!batches.isEmpty)
    #expect(batches.allSatisfy { $0.count <= 250 })
    let total = batches.reduce(0) { $0 + $1.count }
    // drainCDCLimit 500 — some CDC rows may be commit markers filtered out.
    #expect(total >= 400)
    #expect(total <= 600)
    #expect(batches.count >= 2)  // 400+ pending at size 250 ⇒ multiple batches
  }

  @Test func lastWriterWinsConflict() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      conflictPolicy: .lastWriterWins(field: "updatedAt"),
      enablesCloudKit: false
    )
    let engine = try await TursoCKSyncEngine(connection: conn, configuration: config)
    try await engine.start(automaticallySync: false)

    let id = "lw1"
    try await engine.performLocalWrite {
      try await conn.execute(
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

    let failed = try #require(try await engine.makeRecord(for: recordID))
    try await engine.resolveConflictForTesting(failedRecord: failed, serverRecord: server)

    // Local is newer → keep local title, re-pend save.
    let title = try await conn.queryOne("SELECT title FROM notes WHERE id = ?", [.text(id)])?[
      "title"
    ]?.stringValue
    #expect(title == "local")
    let pending = await engine.pendingRecordZoneChanges
    let hasPending = pending.contains {
      if case .saveRecord(let rid) = $0 { return rid.recordName == "notes:\(id)" }
      return false
    }
    #expect(hasPending)
  }

  @Test func serverWinsConflict() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      conflictPolicy: .serverWins,
      enablesCloudKit: false
    )
    let engine = try await TursoCKSyncEngine(connection: conn, configuration: config)
    try await engine.start(automaticallySync: false)

    let id = "sw1"
    try await engine.performLocalWrite {
      try await conn.execute(
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

    let failed = try #require(try await engine.makeRecord(for: recordID))
    try await engine.resolveConflictForTesting(failedRecord: failed, serverRecord: server)

    let title = try await conn.queryOne("SELECT title FROM notes WHERE id = ?", [.text(id)])?[
      "title"
    ]?.stringValue
    #expect(title == "server")
  }

  @Test func clientWinsPreservesLocalPayloadForRetry() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }
    let config = TursoCKSyncConfiguration(
      containerIdentifier: "iCloud.com.turso.cloudkit.tests",
      syncedTables: [notesTable],
      conflictPolicy: .clientWins,
      enablesCloudKit: false
    )
    let engine = try await TursoCKSyncEngine(connection: conn, configuration: config)
    try await engine.start(automaticallySync: false)
    try await engine.performLocalWrite {
      try await conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES ('cw1','local','b','2026-07-22T10:05:00Z')"
      )
    }

    let recordID = CKRecord.ID(recordName: "notes:cw1", zoneID: engine.zoneID)
    let failed = try #require(try await engine.makeRecord(for: recordID))
    let server = CKRecord(recordType: "notes", recordID: recordID)
    server["id"] = "cw1"
    server["title"] = "server"
    server["body"] = "b"
    server["updatedAt"] = "2026-07-22T10:00:00Z"

    try await engine.resolveConflictForTesting(failedRecord: failed, serverRecord: server)

    let outbound = try #require(try await engine.makeRecord(for: recordID))
    #expect(outbound["title"] as? String == "local")
    #expect(
      try await conn.queryOne("SELECT title FROM notes WHERE id = 'cw1'")?["title"]?.stringValue
        == "local")
    let pending = await engine.pendingRecordZoneChanges
    #expect(
      pending.contains { change in
        if case .saveRecord(let id) = change { return id == recordID }
        return false
      })
  }

  @Test func pendingChangesSurviveEngineRestart() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }
    let first = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await first.start(automaticallySync: false)
    try await conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES ('restart','local','b','2026-01-01T00:00:00Z')"
    )
    _ = try await first.drainCDC()
    let cursor = try await first.metadata.loadCDCCursor()
    await first.stop()

    let restarted = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await restarted.start(automaticallySync: false)
    #expect(try await restarted.metadata.loadCDCCursor() == cursor)
    let restartedPending = await restarted.pendingRecordZoneChanges
    #expect(
      restartedPending.contains { change in
        if case .saveRecord(let id) = change { return id.recordName == "notes:restart" }
        return false
      })
  }

  @Test func acknowledgedPendingChangeDoesNotReturnAfterRestart() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }
    let first = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await first.start(automaticallySync: false)
    try await conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES ('acked','local','b','2026-01-01T00:00:00Z')"
    )
    _ = try await first.drainCDC()
    let recordID = CKRecord.ID(recordName: "notes:acked", zoneID: first.zoneID)
    try await first.acknowledgePendingChangeForTesting(recordID: recordID)
    await first.stop()

    let restarted = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await restarted.start(automaticallySync: false)
    let restartedPending = await restarted.pendingRecordZoneChanges
    #expect(
      !restartedPending.contains { change in
        if case .saveRecord(let id) = change { return id == recordID }
        return false
      })
  }

  @Test func missingProviderRowRemovesDurableSave() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }
    let first = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await first.start(automaticallySync: false)
    try await conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES ('missing','local','b','2026-01-01T00:00:00Z')"
    )
    _ = try await first.drainCDC()
    let recordID = CKRecord.ID(recordName: "notes:missing", zoneID: first.zoneID)
    try await conn.execute("DELETE FROM notes WHERE id = 'missing'")

    #expect(try await first.recordForPendingSaveForTesting(recordID: recordID) == nil)
    await first.stop()
    let restarted = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await restarted.start(automaticallySync: false)
    let restartedPending = await restarted.pendingRecordZoneChanges
    #expect(
      !restartedPending.contains { change in
        if case .saveRecord(let id) = change { return id == recordID }
        return false
      })
  }

  @Test func invalidRecordNameDoesNotAdvanceCursor() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }
    let engine = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await engine.start(automaticallySync: false)
    let oversizedID = String(repeating: "x", count: 300)
    try await conn.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES (?, 't', 'b', '2026-01-01T00:00:00Z')",
      [.text(oversizedID)]
    )

    await #expect(throws: TursoCKSyncError.self) {
      _ = try await engine.drainCDC()
    }
    #expect(try await engine.metadata.loadCDCCursor() == 0)
    let pending = await engine.pendingRecordZoneChanges
    #expect(pending.isEmpty)
  }

  @Test func cloudKitRequiresExplicitContainer() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }
    let config = TursoCKSyncConfiguration(
      syncedTables: [notesTable],
      enablesCloudKit: true
    )
    await #expect(throws: TursoCKSyncError.missingCloudKitContainer) {
      _ = try await TursoCKSyncEngine(connection: conn, configuration: config)
    }
  }

  @Test func syncConfigurationRejectsReservedFieldsAndUniqueIndexes() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }
    let reserved = TursoCKSyncConfiguration(
      syncedTables: [SyncedTable(name: "notes", columns: ["recordID"])],
      enablesCloudKit: false
    )
    await #expect(throws: TursoCKSyncError.self) {
      _ = try await TursoCKSyncEngine(connection: conn, configuration: reserved)
    }

    try await conn.execute("CREATE UNIQUE INDEX notes_title_unique ON notes(title)")
    await #expect(
      throws: TursoCKSyncError.uniqueConstraintUnsupported(
        table: "notes",
        index: "notes_title_unique"
      )
    ) {
      _ = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    }
  }

  @Test func inboundEchoSuppressionPreservesInterleavedLocalChange() async throws {
    let (url, primary) = try await makeConnection()
    defer { await primary.close() }
    defer { try? FileManager.default.removeItem(at: url) }
    let secondDatabase = TursoDatabase(url: url)
    let writer = try await secondDatabase.connect(enableCDC: true)
    defer { await writer.close() }
    let engine = try await TursoCKSyncEngine(connection: primary, configuration: syncConfiguration)
    try await engine.start(automaticallySync: false)

    try await writer.execute(
      "INSERT INTO notes (id, title, body, updatedAt) VALUES ('local-interleaved','local','b','2026-01-01T00:00:00Z')"
    )
    let remoteID = CKRecord.ID(recordName: "notes:remote", zoneID: engine.zoneID)
    let remote = CKRecord(recordType: "notes", recordID: remoteID)
    remote["id"] = "remote"
    remote["title"] = "remote"
    remote["body"] = "b"
    remote["updatedAt"] = "2026-01-01T00:00:00Z"
    try await engine.applyRemoteRecord(remote)

    let pending = await engine.pendingRecordZoneChanges
    #expect(
      pending.contains { change in
        if case .saveRecord(let id) = change { return id.recordName == "notes:local-interleaved" }
        return false
      })
  }

  @Test func removingSyncedColumnRequiresExplicitReset() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }
    _ = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    let changed = TursoCKSyncConfiguration(
      syncedTables: [SyncedTable(name: "notes", columns: ["title", "updatedAt"])],
      enablesCloudKit: false
    )
    await #expect(throws: TursoCKSyncError.self) {
      _ = try await TursoCKSyncEngine(connection: conn, configuration: changed)
    }
  }

  @Test func accountHashChangePreservesLocalData() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let engine = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await engine.start(automaticallySync: false)
    try await engine.noteAccountIdentity("account-a")

    try await engine.performLocalWrite {
      try await conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES ('1','t','b','2026-01-01T00:00:00Z')"
      )
    }
    #expect(try await conn.query("SELECT * FROM notes").count == 1)

    try await engine.noteAccountIdentity("account-b")
    // Local user data preserved; metadata wiped and rows re-enqueued.
    #expect(try await conn.query("SELECT * FROM notes").count == 1)
    #expect(try await engine.metadata.loadAccountHash() == "account-b")
  }

  @Test func cloudKitSyncAdapterStatusStream() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let adapter = try await CloudKitSyncAdapter(
      connection: conn,
      configuration: syncConfiguration
    )
    var iterator = await adapter.syncStatus().makeAsyncIterator()
    let first = await iterator.next()
    #expect(first == .idle)

    try await adapter.start()
    _ = try await adapter.drainLocalChanges()
  }

  @Test func transportNeutralRemoteRecordRoundTrip() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let engine = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await engine.start(automaticallySync: false)
    let adapter = await CloudKitSyncAdapter(engine: engine)
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
      try await conn.queryOne("SELECT title FROM notes WHERE id = ?", [.text(id)])?["title"]?
        .stringValue == "Neutral"
    )
    try await adapter.fetchChanges()
    try await adapter.sendChanges()
    try await adapter.syncChanges()

    try await adapter.applyRemoteChanges([.delete(recordName: "notes:\(id)")])
    #expect(try await conn.queryOne("SELECT id FROM notes WHERE id = ?", [.text(id)]) == nil)
  }

  @Test func unreadableCloudKitAssetIsExplicitFailure() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let engine = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await engine.start(automaticallySync: false)
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

    await #expect(throws: TursoCKSyncError.self) {
      try await engine.applyRemoteRecord(record)
    }
  }

  @Test func invalidTransportMetadataIsExplicitFailure() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let engine = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await engine.start(automaticallySync: false)
    let adapter = await CloudKitSyncAdapter(engine: engine)

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

  @Test func wipePreservingDataReenqueues() async throws {
    let (url, conn) = try await makeConnection()
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await conn.close() }

    let engine = try await TursoCKSyncEngine(connection: conn, configuration: syncConfiguration)
    try await engine.start(automaticallySync: false)
    try await engine.performLocalWrite {
      try await conn.execute(
        "INSERT INTO notes (id, title, body, updatedAt) VALUES ('1','t','b','2026-01-01T00:00:00Z')"
      )
    }
    try await engine.wipeAndRebootstrap(preserveLocalUserData: true)
    #expect(try await conn.query("SELECT * FROM notes").count == 1)
    let pending = await engine.pendingRecordZoneChanges
    #expect(!pending.isEmpty)
  }
}
