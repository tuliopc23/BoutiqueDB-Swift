import BoutiqueDB
import Foundation
import StructuredQueries
import StructuredQueriesTurso
import Testing
import TursoKit

@Suite("Turso-exclusive features")
@MainActor
struct TursoFeaturesTests {
  private func tempDB(concurrentWrites: Bool = false) throws -> BoutiqueDB {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-feat-\(UUID().uuidString).db")
    return try BoutiqueDB(
      url: url,
      startListening: false,
      concurrentWrites: concurrentWrites
    )
  }

  @Test func vector32BindableRoundTripLiteral() {
    let v = Vector32([0.1, 0.2, 0.3])
    #expect(v.jsonLiteral == "[0.1,0.2,0.3]")
    #expect(Vector32(rawValue: v.jsonLiteral)?.values.count == 3)
  }

  @Test func vectorDistanceSQLBuilds() async throws {
    let db = try tempDB()
    defer { try? FileManager.default.removeItem(at: db.url) }

    try await db.execute(
      """
      CREATE TABLE docs (
        id TEXT PRIMARY KEY NOT NULL,
        embedding TEXT NOT NULL
      )
      """
    )
    try await db.execute(
      "INSERT INTO docs (id, embedding) VALUES ('a', '[1.0,0.0]'), ('b', '[0.0,1.0]')"
    )

    guard db.capabilities.vectorFunctions else { return }

    let query = Vector32([1.0, 0.0])
    let rows = try await db.read { conn in
      try conn.query(
        """
        SELECT id, vector_distance_cos(embedding, vector32(?)) AS d
        FROM docs
        ORDER BY d ASC
        """,
        [.text(query.jsonLiteral)]
      )
    }
    #expect(rows.first?["id"]?.stringValue == "a")
  }

  @Test func ftsMatchHelperSQLFragment() {
    let frag = SQLQueryExpression("fts_match(\"title\", \(bind: "swift"))", as: Bool.self)
    #expect(!frag.queryFragment.isEmpty)
  }

  @Test func encryptionOpenViaOfficialSdkKitConfig() async throws {
    // Official path: sdk-kit experimental_features=encryption + cipher/hexkey.
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("enc-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }
    // 32-byte key for aegis256 (hex-encoded by BoutiqueDB).
    let db = try BoutiqueDB(
      url: url,
      startListening: false,
      encryption: .aegis256(key: Data(repeating: 0xAB, count: 32)))
    defer { db.close() }
    try await db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
  }

  @Test func multiProcessOpenViaOfficialToken() async throws {
    // Official multiprocess_wal token; single-process open is allowed.
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("mp-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }
    let db = try BoutiqueDB(url: url, startListening: false, multiProcess: true)
    defer { db.close() }
    try await db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
  }

  @Test func cdcAndMVCCSameHandleRejected() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("both-\(UUID().uuidString).db")
    #expect(throws: BoutiqueError.cdcMutuallyExclusiveWithMVCC) {
      _ = try BoutiqueDB(url: url, enableCDC: true, enableMVCC: true)
    }
  }

  @Test func writeConcurrentDualConnection() async throws {
    let db = try tempDB(concurrentWrites: true)
    defer { try? FileManager.default.removeItem(at: db.url) }

    try await db.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL
      )
      """
    )

    // Lazy MVCC connection opens after schema exists (BD-005 dual-connection path).
    try await db.writeConcurrent { conn in
      try conn.execute(
        "INSERT INTO notes (id, title) VALUES (?, ?)",
        [.text("c1"), .text("hello")]
      )
    }

    let count = try await db.read { conn in
      try conn.query("SELECT COUNT(*) AS c FROM notes").first?["c"]?.int64Value
    }
    #expect(count == 1)
    #expect(db.store.generation >= 1)
  }

  @Test func stringQueryBindableEnumPattern() {
    enum Status: String, StringQueryBindable, Sendable {
      case open
      case closed
    }
    let s = Status.open
    #expect(s.queryOutput == .open)
    #expect(s.rawValue == "open")
    #expect(Status(rawValue: "closed") == .closed)
    #expect(Status(rawValue: "nope") == nil)
  }

  @Test func ftsIndexCreateGatedByCapability() async throws {
    let db = try tempDB()
    defer { try? FileManager.default.removeItem(at: db.url) }

    try await db.execute("CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, body TEXT)")
    let idx = FTSIndexDescriptor(table: "notes", columns: ["title", "body"])

    if db.capabilities.ftsIndex {
      try await db.createFTSIndex(idx)
    } else {
      await #expect(throws: BoutiqueError.self) {
        try await db.createFTSIndex(idx)
      }
    }
  }
}
