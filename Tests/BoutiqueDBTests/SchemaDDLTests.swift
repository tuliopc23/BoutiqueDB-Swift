import BoutiqueDB
import Foundation
import Testing

@Suite("Turso schema DDL builders")
@MainActor
struct SchemaDDLTests {
  @Test func ftsIndexDescriptorSQL() {
    let idx = FTSIndexDescriptor(
      table: "notes",
      columns: ["title", "body"],
      tokenizer: .default
    )
    #expect(idx.ddl.contains("USING fts"))
    #expect(idx.ddl.contains("tokenizer = 'default'"))
    #expect(idx.ddl.contains("\"notes\""))
  }

  @Test func vectorIndexDescriptorSQL() {
    let idx = VectorIndexDescriptor(
      table: "documents",
      column: "embedding",
      metric: .cosine
    )
    #expect(idx.ddl.contains("USING vector"))
    #expect(idx.ddl.contains("metric = 'cosine'"))
  }

  @Test func materializedViewDescriptorSQL() {
    let view = MaterializedViewDescriptor(
      name: "customer_totals",
      sourceSQL: "SELECT customer_id, COUNT(*) AS c FROM orders GROUP BY customer_id"
    )
    #expect(view.ddl.hasPrefix("CREATE MATERIALIZED VIEW IF NOT EXISTS"))
    #expect(view.ddl.contains("GROUP BY customer_id"))
  }

  @Test func createAppliesTableDescriptor() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("schema-\(UUID().uuidString).db")
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await db.close() }

    let table = BoutiqueTableDescriptor(
      name: "items",
      columnsSQL: "  \"id\" TEXT PRIMARY KEY NOT NULL,\n  \"title\" TEXT NOT NULL",
      strict: true
    )
    try await db.execute(table.ddl)

    let rows = try await db.read { conn in
      try await conn.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'items'")
    }
    #expect(rows.count == 1)
  }

  @Test func capabilitiesProbeDoesNotThrow() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("cap-\(UUID().uuidString).db")
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await db.close() }

    // CDC path always available through our open path.
    #expect(db.capabilities.cdc)
  }

  @Test func createSchemaTypeWithManualConformance() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("schema2-\(UUID().uuidString).db")
    let db = try await BoutiqueDB(url: url, startListening: false)
    defer { try? FileManager.default.removeItem(at: url) }
    defer { await db.close() }

    try await db.create(ManualNoteSchema.self)
    let rows = try await db.read { conn in
      try await conn.query("SELECT name FROM sqlite_master WHERE name = 'manual_notes'")
    }
    #expect(rows.count == 1)
  }
}

private enum ManualNoteSchema: BoutiqueSchema {
  static var boutiqueTableName: String { "manual_notes" }
  static var boutiqueCreateStatements: [String] {
    [
      """
      CREATE TABLE IF NOT EXISTS "manual_notes" (
        "id" TEXT PRIMARY KEY NOT NULL,
        "title" TEXT NOT NULL
      )
      """
    ]
  }
}
