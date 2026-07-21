import CloudKit
import Foundation
import TursoKit

/// Persists CKSyncEngine state and per-row CloudKit system fields in the Turso file.
public struct SyncMetadataStore: Sendable {
  public static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS ck_sync_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      state_blob BLOB NOT NULL,
      updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS ck_record_meta (
      table_name TEXT NOT NULL,
      row_pk TEXT NOT NULL,
      record_name TEXT NOT NULL,
      zone_name TEXT NOT NULL,
      system_fields BLOB,
      updated_at REAL NOT NULL,
      PRIMARY KEY (table_name, row_pk)
    );

    CREATE UNIQUE INDEX IF NOT EXISTS ck_record_meta_record_name
      ON ck_record_meta(record_name);

    CREATE TABLE IF NOT EXISTS ck_cdc_cursor (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      last_change_id INTEGER NOT NULL DEFAULT 0,
      updated_at REAL NOT NULL
    );

    INSERT OR IGNORE INTO ck_cdc_cursor (id, last_change_id, updated_at)
    VALUES (1, 0, 0);
    """

  private let connection: TursoConnection

  public init(connection: TursoConnection) {
    self.connection = connection
  }

  public func migrate() throws {
    for statement in Self.schemaSQL.split(separator: ";") {
      let sql = statement.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !sql.isEmpty else { continue }
      try connection.execute(sql)
    }
  }

  // MARK: - Engine state

  public func loadStateSerialization() throws -> CKSyncEngine.State.Serialization? {
    guard
      let data = try connection.queryOne("SELECT state_blob FROM ck_sync_state WHERE id = 1")?[
        "state_blob"
      ]?.dataValue
    else { return nil }
    return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
  }

  public func saveStateSerialization(_ state: CKSyncEngine.State.Serialization) throws {
    let data = try JSONEncoder().encode(state)
    try connection.execute(
      """
      INSERT INTO ck_sync_state (id, state_blob, updated_at)
      VALUES (1, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        state_blob = excluded.state_blob,
        updated_at = excluded.updated_at
      """,
      [.blob(data), .double(Date().timeIntervalSince1970)]
    )
  }

  public func clearStateSerialization() throws {
    try connection.execute("DELETE FROM ck_sync_state")
  }

  // MARK: - CDC cursor

  public func loadCDCCursor() throws -> Int64 {
    try connection.queryOne("SELECT last_change_id FROM ck_cdc_cursor WHERE id = 1")?[
      "last_change_id"
    ]?.int64Value ?? 0
  }

  public func saveCDCCursor(_ changeID: Int64) throws {
    try connection.execute(
      """
      UPDATE ck_cdc_cursor
      SET last_change_id = ?, updated_at = ?
      WHERE id = 1
      """,
      [.integer(changeID), .double(Date().timeIntervalSince1970)]
    )
  }

  // MARK: - Record meta

  public func systemFields(table: String, rowPK: String) throws -> Data? {
    try connection.queryOne(
      """
      SELECT system_fields FROM ck_record_meta
      WHERE table_name = ? AND row_pk = ?
      """,
      [.text(table), .text(rowPK)]
    )?["system_fields"]?.dataValue
  }

  public func systemFields(recordName: String) throws -> Data? {
    try connection.queryOne(
      """
      SELECT system_fields FROM ck_record_meta
      WHERE record_name = ?
      """,
      [.text(recordName)]
    )?["system_fields"]?.dataValue
  }

  public func upsertRecordMeta(
    table: String,
    rowPK: String,
    recordName: String,
    zoneName: String,
    systemFields: Data?
  ) throws {
    try connection.execute(
      """
      INSERT INTO ck_record_meta
        (table_name, row_pk, record_name, zone_name, system_fields, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(table_name, row_pk) DO UPDATE SET
        record_name = excluded.record_name,
        zone_name = excluded.zone_name,
        system_fields = excluded.system_fields,
        updated_at = excluded.updated_at
      """,
      [
        .text(table),
        .text(rowPK),
        .text(recordName),
        .text(zoneName),
        systemFields.map { .blob($0) } ?? .null,
        .double(Date().timeIntervalSince1970),
      ]
    )
  }

  public func deleteRecordMeta(table: String, rowPK: String) throws {
    try connection.execute(
      """
      DELETE FROM ck_record_meta
      WHERE table_name = ? AND row_pk = ?
      """,
      [.text(table), .text(rowPK)]
    )
  }

  public func deleteRecordMeta(recordName: String) throws {
    try connection.execute(
      "DELETE FROM ck_record_meta WHERE record_name = ?",
      [.text(recordName)]
    )
  }

  public func resolveRow(recordName: String) throws -> (table: String, rowPK: String)? {
    guard
      let row = try connection.queryOne(
        "SELECT table_name, row_pk FROM ck_record_meta WHERE record_name = ?",
        [.text(recordName)]
      ),
      let table = row["table_name"]?.stringValue,
      let rowPK = row["row_pk"]?.stringValue
    else { return nil }
    return (table, rowPK)
  }

  public func wipeAll() throws {
    try connection.execute("DELETE FROM ck_record_meta")
    try connection.execute("DELETE FROM ck_sync_state")
    try connection.execute(
      """
      UPDATE ck_cdc_cursor
      SET last_change_id = 0, updated_at = ?
      WHERE id = 1
      """,
      [.double(Date().timeIntervalSince1970)]
    )
  }
}
