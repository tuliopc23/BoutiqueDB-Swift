import BoutiqueDB
import Foundation
import StructuredQueries
import Testing
import TursoCKSync
import TursoKit

@Table
struct StressNote: Sendable {
  @Column(primaryKey: true) let id: String
  var title: String
}

@Suite("Refinement stress")
@MainActor
struct RefinementStressTests {
  @Test func dualLiveQueryWithWritesAndDrain() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("stress-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let plan = BoutiqueMigrationPlan {
      BoutiqueMigration(
        "v1",
        asynchronous: { db in
          try await db.execute(
            """
            CREATE TABLE stressNotes (
              id TEXT PRIMARY KEY NOT NULL,
              title TEXT NOT NULL
            )
            """
          )
        })
    }
    let db = try await BoutiqueDB.open(
      url: url,
      startListening: true,
      concurrentWrites: true,
      migrations: plan)
    defer { db.close() }

    let a = LiveQuery(db) { StressNote.all.asSelect() }
    let b = LiveQuery(db) { StressNote.all.asSelect() }

    try await db.write { conn in
      try conn.execute(
        "INSERT INTO stressNotes (id, title) VALUES (?, ?)",
        [.text("1"), .text("one")]
      )
    }
    try await db.writeConcurrent { conn in
      try conn.execute(
        "INSERT INTO stressNotes (id, title) VALUES (?, ?)",
        [.text("2"), .text("two")]
      )
    }

    let engine = try TursoCKSyncEngine(
      connection: db.unsafeConnection,
      configuration: TursoCKSyncConfiguration(
        syncedTables: [SyncedTable(name: "stressNotes", columns: ["title"])],
        enablesCloudKit: false
      )
    )
    try engine.start(automaticallySync: false)
    _ = try engine.drainCDC()

    // Wait for both LiveQueries
    let clock = ContinuousClock()
    let deadline = clock.now + .milliseconds(800)
    while clock.now < deadline {
      if a.wrappedValue.count >= 2 && b.wrappedValue.count >= 2 { break }
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(a.wrappedValue.count >= 2)
    #expect(b.wrappedValue.count >= 2)
    #expect(!engine.pendingRecordZoneChanges.isEmpty)
  }

  @Test func liveQuerySetQueryReloads() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lq-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try BoutiqueDB(url: url, startListening: false)
    defer { db.close() }
    try await db.execute(
      """
      CREATE TABLE stressNotes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )
    try await db.write { conn in
      try conn.execute(
        "INSERT INTO stressNotes (id, title) VALUES ('a','alpha'), ('b','beta')"
      )
    }

    let q = LiveQuery(db) { StressNote.all.asSelect() }
    await q.load()
    #expect(q.wrappedValue.count == 2)

    q.setQuery {
      StressNote.where { $0.title.eq("alpha") }.asSelect()
    }
    // setQuery schedules refresh asynchronously
    let clock = ContinuousClock()
    let deadline = clock.now + .milliseconds(500)
    while clock.now < deadline {
      if q.wrappedValue.count == 1 { break }
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(q.wrappedValue.map(\.id) == ["a"])
  }
}
