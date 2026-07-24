import BoutiqueDB
import Foundation
import Observation
import StructuredQueries
import Testing
import TursoKit
import TursoObservation

@Table
struct Note: Sendable {
  @Column(primaryKey: true) let id: String
  var title: String
  var body: String
}

@Suite("BoutiqueDB high-level API")
@MainActor
struct BoutiqueDBTests {
  private func makeDBWithSchema(startListening: Bool = false) async throws -> BoutiqueDB {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("boutique-\(UUID().uuidString).db")
    let db = try await BoutiqueDB(url: url, startListening: startListening)
    try await db.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL
      )
      """
    )
    return db
  }

  private func waitFor(
    timeout: Duration = .milliseconds(500),
    poll: Duration = .milliseconds(5),
    _ condition: @MainActor () async -> Bool
  ) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: poll)
    }
    return await condition()
  }

  @Test func asyncReadWriteRoundTrip() async throws {
    let db = try await makeDBWithSchema()
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: db.url)
    }

    try await db.write { conn in
      try await Note.insert { Note(id: "n1", title: "Hello", body: "World") }.execute(
        conn.connection)
    }

    let all = try await db.fetchAll(Note.self)
    #expect(all.map(\.id) == ["n1"])

    let one = try await db.fetchOne(Note.self, key: "n1")
    #expect(one?.title == "Hello")
  }

  @Test func writeEmitsChangeEvent() async throws {
    let db = try await makeDBWithSchema()
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: db.url)
    }

    let stream = db.store.subscribe()
    var iterator = stream.makeAsyncIterator()

    try await db.write { conn in
      try await Note.insert { Note(id: "evt", title: "E", body: "B") }.execute(conn.connection)
    }

    let event = await iterator.next()
    guard case .generation(let gen)? = event else {
      Issue.record("Expected generation change event")
      return
    }
    #expect(gen >= 1)
  }

  @Test func liveQueryAutoRefreshes() async throws {
    let db = try await makeDBWithSchema()
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: db.url)
    }

    let query = LiveQuery(db) { Note.all.asSelect() }
    _ = await waitFor(timeout: .milliseconds(500)) {
      !query.isLoading
    }

    try await db.write { conn in
      try await Note.insert { Note(id: "n2", title: "A", body: "B") }.execute(conn.connection)
    }

    let updated = await waitFor(timeout: .milliseconds(500)) {
      query.wrappedValue.map(\.id) == ["n2"]
    }
    #expect(updated)
    #expect(query.wrappedValue.map(\.id) == ["n2"])
  }

  @Test func liveQueryOneAutoRefreshes() async throws {
    let db = try await makeDBWithSchema()
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: db.url)
    }

    try await db.write { conn in
      try await Note.insert { Note(id: "n3", title: "One", body: "1") }.execute(conn.connection)
    }

    let query = LiveQueryOne(db) { Note.where { $0.id.eq("n3") }.asSelect() }
    let loaded = await waitFor(timeout: .milliseconds(500)) {
      query.wrappedValue?.title == "One"
    }
    #expect(loaded)
    #expect(query.wrappedValue?.title == "One")

    try await db.write { conn in
      try await Note.where { $0.id.eq("n3") }.update { $0.title = "Two" }.execute(conn.connection)
    }

    let refreshed = await waitFor(timeout: .milliseconds(500)) {
      query.wrappedValue?.title == "Two"
    }
    #expect(refreshed)
  }

  @Test func twoLiveQueriesBothRefresh() async throws {
    let db = try await makeDBWithSchema()
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: db.url)
    }

    let a = LiveQuery(db) { Note.all.asSelect() }
    let b = LiveQuery(db) { Note.all.asSelect() }

    try await db.write { conn in
      try await Note.insert { Note(id: "dual", title: "D", body: "B") }.execute(conn.connection)
    }

    let both = await waitFor(timeout: .milliseconds(500)) {
      a.wrappedValue.map(\.id) == ["dual"] && b.wrappedValue.map(\.id) == ["dual"]
    }
    #expect(both)
  }

  @Test func forceRefreshWorks() async throws {
    let db = try await makeDBWithSchema()
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: db.url)
    }

    let query = LiveQuery(db) { Note.all.asSelect() }
    _ = await waitFor { !query.isLoading }

    try await db.unsafeConnection.execute(
      "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
      [.text("force"), .text("F"), .text("B")]
    )
    await db.store.advanceFromCDC()
    await query.load()
    #expect(query.wrappedValue.map(\.id) == ["force"])
  }

  @Test func concurrentWritesSerialize() async throws {
    let db = try await makeDBWithSchema()
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: db.url)
    }

    async let w1: Void = db.write { conn in
      try await Note.insert { Note(id: "c1", title: "1", body: "a") }.execute(conn.connection)
    }
    async let w2: Void = db.write { conn in
      try await Note.insert { Note(id: "c2", title: "2", body: "b") }.execute(conn.connection)
    }
    _ = try await (w1, w2)

    let all = try await db.fetchAll(Note.self)
    #expect(Set(all.map(\.id)) == Set(["c1", "c2"]))
  }

  @Test func cdcAndMVCCAreMutuallyExclusive() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("boutique-mvcc-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: BoutiqueError.cdcMutuallyExclusiveWithMVCC) {
      _ = try await BoutiqueDB(url: url, enableCDC: true, enableMVCC: true)
    }
  }

  @Test func boutiqueErrorCasesExist() {
    let errors: [BoutiqueError] = [
      .cdcMutuallyExclusiveWithMVCC,
      .encryptionUnavailable,
      .multiProcessWALUnavailable,
      .featureUnavailable("vector"),
      .sql(code: 1, message: "test"),
      .closed,
      .transactionInProgress,
      .invalidTransactionState("x"),
      .postCommitObserverFailed("x"),
      .invalidMigrationPlan("x"),
      .migrationFailed(id: "v1", message: "x"),
      .schemaErasedForDebug("x"),
    ]
    #expect(errors.count == 12)
  }

  @Test func postCommitObserversDoNotClobberAndFailuresAreVisible() async throws {
    let db = try await makeDBWithSchema()
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: db.url)
    }
    var calls = 0
    _ = db.addPostCommitObserver { calls += 1 }
    _ = db.addPostCommitObserver {
      calls += 1
      throw TursoError(code: 1, message: "enqueue failed")
    }

    try await db.execute("INSERT INTO notes (id, title, body) VALUES ('hooks', 'H', 'B')")
    #expect(calls == 2)
    #expect(db.lastPostCommitError == .postCommitObserverFailed("TursoError(1): enqueue failed"))
  }
}
