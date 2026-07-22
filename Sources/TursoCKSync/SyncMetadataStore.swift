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

    CREATE TABLE IF NOT EXISTS ck_account (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      account_hash TEXT,
      updated_at REAL NOT NULL
    );

    INSERT OR IGNORE INTO ck_account (id, account_hash, updated_at)
    VALUES (1, NULL, 0);

    CREATE TABLE IF NOT EXISTS ck_meta_version (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      format_version INTEGER NOT NULL DEFAULT 1,
      updated_at REAL NOT NULL
    );

    INSERT OR IGNORE INTO ck_meta_version (id, format_version, updated_at)
    VALUES (1, 1, 0);

    CREATE TABLE IF NOT EXISTS ck_pending_changes (
      record_name TEXT PRIMARY KEY NOT NULL,
      table_name TEXT NOT NULL,
      row_pk TEXT NOT NULL,
      zone_name TEXT NOT NULL,
      operation INTEGER NOT NULL,
      change_id INTEGER NOT NULL,
      updated_at REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS ck_synced_schema (
      table_name TEXT PRIMARY KEY NOT NULL,
      primary_key TEXT NOT NULL,
      columns_json TEXT NOT NULL,
      record_type TEXT NOT NULL
    );
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
    try saveFormatVersion(Self.currentFormatVersion)
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

  func stagePendingChanges(_ changes: [DurablePendingChange], through changeID: Int64) throws {
    try connection.write {
      try stagePendingChangesInCurrentTransaction(changes, through: changeID)
    }
  }

  func stagePendingChangesInCurrentTransaction(
    _ changes: [DurablePendingChange],
    through changeID: Int64
  ) throws {
    for change in changes {
      try connection.execute(
        """
        INSERT INTO ck_pending_changes
          (record_name, table_name, row_pk, zone_name, operation, change_id, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(record_name) DO UPDATE SET
          table_name = excluded.table_name,
          row_pk = excluded.row_pk,
          zone_name = excluded.zone_name,
          operation = excluded.operation,
          change_id = excluded.change_id,
          updated_at = excluded.updated_at
        """,
        [
          .text(change.recordName), .text(change.tableName), .text(change.rowPK),
          .text(change.zoneName), .integer(change.operation.rawValue), .integer(change.changeID),
          .double(Date().timeIntervalSince1970),
        ]
      )
    }
    try saveCDCCursor(changeID)
  }

  func loadPendingChanges() throws -> [DurablePendingChange] {
    try connection.query(
      """
      SELECT record_name, table_name, row_pk, zone_name, operation, change_id
      FROM ck_pending_changes
      ORDER BY change_id ASC, record_name ASC
      """
    ).compactMap { row in
      guard let recordName = row["record_name"]?.stringValue,
        let tableName = row["table_name"]?.stringValue,
        let rowPK = row["row_pk"]?.stringValue,
        let zoneName = row["zone_name"]?.stringValue,
        let operationValue = row["operation"]?.int64Value,
        let operation = DurablePendingChange.Operation(rawValue: operationValue),
        let changeID = row["change_id"]?.int64Value
      else { return nil }
      return DurablePendingChange(
        recordName: recordName,
        tableName: tableName,
        rowPK: rowPK,
        zoneName: zoneName,
        operation: operation,
        changeID: changeID
      )
    }
  }

  func removePendingChange(recordName: String) throws {
    try connection.execute(
      "DELETE FROM ck_pending_changes WHERE record_name = ?",
      [.text(recordName)]
    )
  }

  func removeAllPendingChanges() throws {
    try connection.execute("DELETE FROM ck_pending_changes")
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
    try connection.execute("DELETE FROM ck_pending_changes")
    try connection.execute(
      """
      UPDATE ck_cdc_cursor
      SET last_change_id = 0, updated_at = ?
      WHERE id = 1
      """,
      [.double(Date().timeIntervalSince1970)]
    )
    try connection.execute(
      """
      UPDATE ck_account
      SET account_hash = NULL, updated_at = ?
      WHERE id = 1
      """,
      [.double(Date().timeIntervalSince1970)]
    )
  }

  // MARK: - Account identity (BD-007)

  public func loadAccountHash() throws -> String? {
    try connection.queryOne("SELECT account_hash FROM ck_account WHERE id = 1")?[
      "account_hash"
    ]?.stringValue
  }

  public func saveAccountHash(_ hash: String?) throws {
    try connection.execute(
      """
      INSERT INTO ck_account (id, account_hash, updated_at)
      VALUES (1, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        account_hash = excluded.account_hash,
        updated_at = excluded.updated_at
      """,
      [
        hash.map { .text($0) } ?? .null,
        .double(Date().timeIntervalSince1970),
      ]
    )
  }

  /// Sync metadata format version (bump when on-disk layout changes incompatibly).
  public static let currentFormatVersion: Int64 = 2

  public func loadFormatVersion() throws -> Int64 {
    try connection.queryOne("SELECT format_version FROM ck_meta_version WHERE id = 1")?[
      "format_version"
    ]?.int64Value ?? 1
  }

  public func saveFormatVersion(_ version: Int64 = SyncMetadataStore.currentFormatVersion) throws {
    try connection.execute(
      """
      INSERT INTO ck_meta_version (id, format_version, updated_at)
      VALUES (1, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        format_version = excluded.format_version,
        updated_at = excluded.updated_at
      """,
      [.integer(version), .double(Date().timeIntervalSince1970)]
    )
  }

  func validateAndSaveSchema(_ tables: [SyncedTable]) throws {
    let existingRows = try connection.query(
      "SELECT table_name, primary_key, columns_json, record_type FROM ck_synced_schema"
    )
    var existing: [String: PersistedSyncedTableSchema] = [:]
    for row in existingRows {
      guard let tableName = row["table_name"]?.stringValue,
        let primaryKey = row["primary_key"]?.stringValue,
        let columnsJSON = row["columns_json"]?.stringValue,
        let data = columnsJSON.data(using: .utf8),
        let columns = try? JSONDecoder().decode([String].self, from: data),
        let recordType = row["record_type"]?.stringValue
      else {
        throw TursoCKSyncError.invalidConfiguration("Stored sync schema metadata is invalid")
      }
      existing[tableName] = PersistedSyncedTableSchema(
        primaryKey: primaryKey,
        columns: columns,
        recordType: recordType
      )
    }

    let currentNames = Set(tables.map(\.name))
    if let removed = existing.keys.first(where: { !currentNames.contains($0) }) {
      throw TursoCKSyncError.incompatibleSchemaMigration(
        table: removed,
        reason: "removing a previously synced table is unsupported"
      )
    }

    try connection.write {
      for table in tables {
        if let previous = existing[table.name] {
          guard previous.primaryKey == table.primaryKeyColumn else {
            throw TursoCKSyncError.incompatibleSchemaMigration(
              table: table.name,
              reason:
                "primary key changed from '\(previous.primaryKey)' to '\(table.primaryKeyColumn)'"
            )
          }
          guard previous.recordType == table.recordType else {
            throw TursoCKSyncError.incompatibleSchemaMigration(
              table: table.name,
              reason: "CloudKit record type changed"
            )
          }
          let removedColumns = Set(previous.columns).subtracting(table.columns)
          guard removedColumns.isEmpty else {
            throw TursoCKSyncError.incompatibleSchemaMigration(
              table: table.name,
              reason: "removed synced columns \(removedColumns.sorted())"
            )
          }
        }
        let columnsData = try JSONEncoder().encode(table.columns)
        guard let columnsJSON = String(data: columnsData, encoding: .utf8) else {
          throw TursoCKSyncError.invalidConfiguration("Cannot encode sync schema metadata")
        }
        try connection.execute(
          """
          INSERT INTO ck_synced_schema (table_name, primary_key, columns_json, record_type)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(table_name) DO UPDATE SET
            primary_key = excluded.primary_key,
            columns_json = excluded.columns_json,
            record_type = excluded.record_type
          """,
          [
            .text(table.name), .text(table.primaryKeyColumn), .text(columnsJSON),
            .text(table.recordType),
          ]
        )
      }
    }
  }
}

struct DurablePendingChange: Sendable, Equatable {
  enum Operation: Int64, Sendable {
    case save = 1
    case delete = -1
  }

  var recordName: String
  var tableName: String
  var rowPK: String
  var zoneName: String
  var operation: Operation
  var changeID: Int64
}

private struct PersistedSyncedTableSchema: Sendable {
  var primaryKey: String
  var columns: [String]
  var recordType: String
}
