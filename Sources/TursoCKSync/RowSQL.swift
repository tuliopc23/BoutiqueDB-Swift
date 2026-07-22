import Foundation
import TursoKit

enum RowSQL {
  static func quoteIdent(_ name: String) -> String {
    "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
  }

  static func fetchRow(
    connection: TursoConnection,
    table: SyncedTable,
    rowPK: String
  ) throws -> [String: TursoValue]? {
    let sql = """
      SELECT * FROM \(quoteIdent(table.name))
      WHERE \(quoteIdent(table.primaryKeyColumn)) = ?
      LIMIT 1
      """
    return try connection.queryOne(sql, [.text(rowPK)])
  }

  static func upsert(
    connection: TursoConnection,
    table: SyncedTable,
    row: [String: TursoValue]
  ) throws {
    guard let pk = row[table.primaryKeyColumn] else {
      throw TursoError(code: -1, message: "Missing primary key for \(table.name)")
    }
    var columns = [table.primaryKeyColumn] + table.columns
    // Deduplicate if PK was also listed in columns.
    var seen = Set<String>()
    columns = columns.filter { seen.insert($0).inserted }

    let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
    let columnList = columns.map(quoteIdent).joined(separator: ", ")
    let updates =
      columns
      .filter { $0 != table.primaryKeyColumn }
      .map { "\(quoteIdent($0)) = excluded.\(quoteIdent($0))" }
      .joined(separator: ", ")

    let sql: String
    if updates.isEmpty {
      sql = """
        INSERT INTO \(quoteIdent(table.name)) (\(columnList))
        VALUES (\(placeholders))
        ON CONFLICT(\(quoteIdent(table.primaryKeyColumn))) DO NOTHING
        """
    } else {
      sql = """
        INSERT INTO \(quoteIdent(table.name)) (\(columnList))
        VALUES (\(placeholders))
        ON CONFLICT(\(quoteIdent(table.primaryKeyColumn))) DO UPDATE SET
          \(updates)
        """
    }

    let bindings = columns.map { row[$0] ?? .null }
    _ = pk
    try connection.execute(sql, bindings)
  }

  static func delete(
    connection: TursoConnection,
    table: SyncedTable,
    rowPK: String
  ) throws {
    let sql = """
      DELETE FROM \(quoteIdent(table.name))
      WHERE \(quoteIdent(table.primaryKeyColumn)) = ?
      """
    try connection.execute(sql, [.text(rowPK)])
  }

  static func deleteAllSyncedData(
    connection: TursoConnection,
    tables: [SyncedTable]
  ) throws {
    for table in tables {
      try connection.execute("DELETE FROM \(quoteIdent(table.name))")
    }
  }
}
