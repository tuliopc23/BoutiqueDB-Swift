import Foundation
import StructuredQueries
import StructuredQueriesTurso
import Testing
import TursoKit

@Suite("TursoKit embed + CDC")
struct TursoKitTests {
  @Test func openCRUDAndCDC() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-kit-\(UUID().uuidString).db")

    let db = TursoDatabase(url: url)
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: url)
    }
    let conn = try await db.connect(enableCDC: true)
    defer { await conn.close() }

    try await conn.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL
      )
      """
    )

    let id = UUID().uuidString
    try await conn.execute(
      "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
      [.text(id), .text("Hello"), .text("World")]
    )

    let row = try await conn.queryOne("SELECT title, body FROM notes WHERE id = ?", [.text(id)])
    #expect(row?["title"]?.stringValue == "Hello")
    #expect(row?["body"]?.stringValue == "World")

    let changes = try await conn.cdcChanges(after: 0)
    #expect(!changes.isEmpty)
    #expect(changes.contains { $0.tableName == "notes" && $0.isInsert })

    let decoded = try await conn.cdcDecodedJSON(after: 0)
    #expect(!decoded.isEmpty)
    #expect(decoded.contains { $0["table_name"]?.stringValue == "notes" })
  }

  @Test func structuredQueriesDriver() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-sq-\(UUID().uuidString).db")
    let db = TursoDatabase(url: url)
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: url)
    }

    let conn = try await db.connect()
    defer { await conn.close() }
    try await conn.execute(
      """
      CREATE TABLE "notes" (
        "id" TEXT PRIMARY KEY NOT NULL,
        "title" TEXT NOT NULL,
        "body" TEXT NOT NULL
      )
      """
    )

    try await Note.insert {
      Note(id: "n1", title: "Alpha", body: "a")
    }.execute(conn)

    try await Note.insert {
      Note(id: "n2", title: "Beta", body: "b")
    }.execute(conn)

    let all = try await Note.order { $0.title }.fetchAll(conn)
    #expect(all.map(\.id) == ["n1", "n2"])

    let one = try await Note.where { $0.id.eq("n2") }.fetchOne(conn)
    #expect(one?.title == "Beta")

    try await Note.where { $0.id.eq("n1") }.update { $0.title = "Alpha2" }.execute(conn)
    #expect(try await Note.find(conn, key: "n1").title == "Alpha2")

    try await Note.where { $0.id.eq("n2") }.delete().execute(conn)
    #expect(try await Note.fetchCount(conn) == 1)
  }

  @Test func clearBindingsNeverSilentlySucceeds() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-clear-bindings-\(UUID().uuidString).db")
    let db = TursoDatabase(url: url)
    defer {
      await db.close()
      try? FileManager.default.removeItem(at: url)
    }
    let conn = try await db.connect()
    defer { await conn.close() }

    try await conn.withPreparedStatement("SELECT ?") { statement in
      try statement.bind(.integer(42), at: 1)
      #expect(throws: TursoError.self) {
        try statement.clearBindings()
      }
      return ()
    }
  }

  @Test func databaseCloseIsIdempotentAndClosesChildren() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-close-\(UUID().uuidString).db")
    let db = TursoDatabase(url: url)
    let conn = try await db.connect()
    await db.close()
    await db.close()
    await #expect(throws: TursoError.self) {
      try await conn.execute("SELECT 1")
    }
    await #expect(throws: TursoError.self) {
      _ = try await db.connect()
    }
    try? FileManager.default.removeItem(at: url)
  }
}

@Table
struct Note: Sendable {
  let id: String
  var title: String
  var body: String
}
