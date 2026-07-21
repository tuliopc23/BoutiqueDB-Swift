import Foundation
import StructuredQueries
import StructuredQueriesTurso
import Testing
import TursoKit

@Suite("TursoKit embed + CDC")
struct TursoKitTests {
  @Test func openCRUDAndCDC() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-kit-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let db = TursoDatabase(url: url)
    let conn = try db.connect(enableCDC: true)

    try conn.execute(
      """
      CREATE TABLE notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL
      )
      """
    )

    let id = UUID().uuidString
    try conn.execute(
      "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
      [.text(id), .text("Hello"), .text("World")]
    )

    let row = try conn.queryOne("SELECT title, body FROM notes WHERE id = ?", [.text(id)])
    #expect(row?["title"]?.stringValue == "Hello")
    #expect(row?["body"]?.stringValue == "World")

    let changes = try conn.cdcChanges(after: 0)
    #expect(!changes.isEmpty)
    #expect(changes.contains { $0.tableName == "notes" && $0.isInsert })

    let decoded = try conn.cdcDecodedJSON(after: 0)
    #expect(!decoded.isEmpty)
    #expect(decoded.contains { $0["table_name"]?.stringValue == "notes" })
  }

  @Test func structuredQueriesDriver() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("turso-sq-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }

    let conn = try TursoDatabase(url: url).connect()
    try conn.execute(
      """
      CREATE TABLE "notes" (
        "id" TEXT PRIMARY KEY NOT NULL,
        "title" TEXT NOT NULL,
        "body" TEXT NOT NULL
      )
      """
    )

    try Note.insert {
      Note(id: "n1", title: "Alpha", body: "a")
    }.execute(conn)

    try Note.insert {
      Note(id: "n2", title: "Beta", body: "b")
    }.execute(conn)

    let all = try Note.order { $0.title }.fetchAll(conn)
    #expect(all.map(\.id) == ["n1", "n2"])

    let one = try Note.where { $0.id.eq("n2") }.fetchOne(conn)
    #expect(one?.title == "Beta")

    try Note.where { $0.id.eq("n1") }.update { $0.title = "Alpha2" }.execute(conn)
    #expect(try Note.find(conn, key: "n1").title == "Alpha2")

    try Note.where { $0.id.eq("n2") }.delete().execute(conn)
    #expect(try Note.fetchCount(conn) == 1)
  }
}

@Table
struct Note {
  let id: String
  var title: String
  var body: String
}
