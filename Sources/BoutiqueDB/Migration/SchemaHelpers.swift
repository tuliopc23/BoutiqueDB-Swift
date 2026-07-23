import Foundation
import TursoKit

extension BoutiqueDB {
  /// Adds a column if it does not already exist (`ALTER TABLE … ADD COLUMN`).
  ///
  /// Safe additive helper for migrations (Room/SwiftData lightweight style).
  public func ensureColumn(
    table: String,
    name: String,
    sqlType: String,
    default defaultSQL: String? = nil
  ) async throws {
    let exists = try await columnExists(table: table, name: name)
    if exists { return }

    var sql =
      "ALTER TABLE \(quoteIdent(table)) ADD COLUMN \(quoteIdent(name)) \(sqlType)"
    if let defaultSQL {
      sql += " DEFAULT \(defaultSQL)"
    }
    try await execute(sql)
  }

  /// Whether a user table exists in `sqlite_master`.
  public func tableExists(_ table: String) async throws -> Bool {
    let rows = try await read { conn in
      try await conn.query(
        """
        SELECT 1 AS ok FROM sqlite_master
        WHERE type = 'table' AND name = ?
        LIMIT 1
        """,
        [.text(table)]
      )
    }
    return !rows.isEmpty
  }

  /// Whether a column exists on `table` (`PRAGMA table_info`).
  public func columnExists(table: String, name: String) async throws -> Bool {
    let rows = try await read { conn in
      try await conn.query("PRAGMA table_info(\(quoteIdent(table)))")
    }
    return rows.contains { row in
      row["name"]?.stringValue == name
    }
  }

  /// Drops a table if present. Explicit-only — never used by additive schema sync.
  public func dropTableIfExists(_ table: String) async throws {
    try await execute("DROP TABLE IF EXISTS \(quoteIdent(table))")
  }
}
