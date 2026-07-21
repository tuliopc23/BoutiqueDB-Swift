import CTursoSQLite3
import Foundation

public enum CDCCaptureMode: String, Sendable {
  case off
  case id
  case before
  case after
  case full
}

/// A single connection to a Turso Database file.
///
/// - Important: Do not enable `journal_mode=mvcc` on a connection that also
///   enables CDC (`PRAGMA capture_data_changes_conn`). They are mutually exclusive.
public final class TursoConnection: @unchecked Sendable {
  public private(set) weak var database: TursoDatabase?
  let handle: OpaquePointer
  private let lock = NSRecursiveLock()
  private var closed = false

  /// Set while applying inbound CloudKit changes so CDC→pending can be skipped.
  public var isSynchronizing: Bool = false

  init(database: TursoDatabase, handle: OpaquePointer) {
    self.database = database
    self.handle = handle
  }

  deinit {
    close()
  }

  public func close() {
    lock.lock()
    defer { lock.unlock() }
    guard !closed else { return }
    closed = true
    database?.unregister(self)
    _ = sqlite3_close(handle)
  }

  // MARK: - Execute / Query

  public func execute(_ sql: String, _ bindings: [TursoValue] = []) throws {
    try withLock {
      let statement = try TursoStatement(db: handle, sql: sql)
      defer { statement.finalize() }
      try statement.bind(bindings)
      while try statement.step() {}
    }
  }

  @discardableResult
  public func executeUpdate(_ sql: String, _ bindings: [TursoValue] = []) throws -> Int {
    try execute(sql, bindings)
    return Int(sqlite3_changes(handle))
  }

  public func query(_ sql: String, _ bindings: [TursoValue] = []) throws -> [[String: TursoValue]] {
    try withLock {
      let statement = try TursoStatement(db: handle, sql: sql)
      defer { statement.finalize() }
      try statement.bind(bindings)
      var rows: [[String: TursoValue]] = []
      while try statement.step() {
        rows.append(statement.namedRow())
      }
      return rows
    }
  }

  public func queryOne(_ sql: String, _ bindings: [TursoValue] = []) throws -> [String: TursoValue]? {
    try query(sql, bindings).first
  }

  public func prepare(_ sql: String) throws -> TursoStatement {
    try withLock {
      try TursoStatement(db: handle, sql: sql)
    }
  }

  /// Prepares `sql`, runs `body`, then finalizes the statement.
  public func withPreparedStatement<T>(
    _ sql: String,
    _ body: (TursoStatement) throws -> T
  ) throws -> T {
    try withLock {
      let statement = try TursoStatement(db: handle, sql: sql)
      defer { statement.finalize() }
      return try body(statement)
    }
  }

  public func lastInsertRowID() -> Int64 {
    sqlite3_last_insert_rowid(handle)
  }

  // MARK: - Transactions

  public func write<T>(_ body: () throws -> T) throws -> T {
    try withLock {
      try executeUnlocked("BEGIN IMMEDIATE")
      do {
        let value = try body()
        try executeUnlocked("COMMIT")
        return value
      } catch {
        try? executeUnlocked("ROLLBACK")
        throw error
      }
    }
  }

  public func read<T>(_ body: () throws -> T) throws -> T {
    try withLock {
      try executeUnlocked("BEGIN")
      do {
        let value = try body()
        try executeUnlocked("COMMIT")
        return value
      } catch {
        try? executeUnlocked("ROLLBACK")
        throw error
      }
    }
  }

  // MARK: - CDC

  public func enableCaptureDataChanges(mode: CDCCaptureMode) throws {
    try execute("PRAGMA capture_data_changes_conn('\(mode.rawValue)')")
  }

  public func cdcChanges(after changeID: Int64, limit: Int = 500) throws -> [CDCChange] {
    let rows = try query(
      """
      SELECT change_id, change_time, change_type, table_name, id, before, after
      FROM turso_cdc
      WHERE change_id > ?
        AND change_type != 2
      ORDER BY change_id ASC
      LIMIT ?
      """,
      [.integer(changeID), .integer(Int64(limit))]
    )
    return rows.compactMap { CDCChange(row: $0) }
  }

  /// Decodes CDC `after`/`before` blobs via Turso SQL helpers.
  public func cdcDecodedJSON(after changeID: Int64, limit: Int = 500) throws -> [[String: TursoValue]] {
    try query(
      """
      SELECT
        c.change_id,
        c.change_time,
        c.change_type,
        c.table_name,
        c.id AS row_id,
        CASE
          WHEN c.change_type = -1 THEN
            bin_record_json_object(table_columns_json_array(c.table_name), c.before)
          ELSE
            bin_record_json_object(table_columns_json_array(c.table_name), c.after)
        END AS payload
      FROM turso_cdc AS c
      WHERE c.change_id > ?
        AND c.change_type != 2
      ORDER BY c.change_id ASC
      LIMIT ?
      """,
      [.integer(changeID), .integer(Int64(limit))]
    )
  }

  // MARK: - Internals

  func withLock<T>(_ body: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    guard !closed else {
      throw TursoError(code: SQLITE_MISUSE, message: "Connection is closed")
    }
    return try body()
  }

  func executeUnlocked(_ sql: String, _ bindings: [TursoValue] = []) throws {
    let statement = try TursoStatement(db: handle, sql: sql)
    defer { statement.finalize() }
    try statement.bind(bindings)
    while try statement.step() {}
  }

  func queryUnlocked(_ sql: String, _ bindings: [TursoValue] = []) throws -> [[String: TursoValue]] {
    let statement = try TursoStatement(db: handle, sql: sql)
    defer { statement.finalize() }
    try statement.bind(bindings)
    var rows: [[String: TursoValue]] = []
    while try statement.step() {
      rows.append(statement.namedRow())
    }
    return rows
  }
}

// MARK: - CDC model

public struct CDCChange: Sendable, Equatable {
  public var changeID: Int64
  public var changeTime: Int64
  /// `1` = INSERT, `0` = UPDATE, `-1` = DELETE, `2` = COMMIT (filtered out).
  public var changeType: Int64
  public var tableName: String
  public var rowID: TursoValue
  public var before: Data?
  public var after: Data?

  public var isInsert: Bool { changeType == 1 }
  public var isUpdate: Bool { changeType == 0 }
  public var isDelete: Bool { changeType == -1 }

  init?(row: [String: TursoValue]) {
    guard
      let changeID = row["change_id"]?.int64Value,
      let changeType = row["change_type"]?.int64Value,
      let tableName = row["table_name"]?.stringValue
    else { return nil }
    self.changeID = changeID
    self.changeTime = row["change_time"]?.int64Value ?? 0
    self.changeType = changeType
    self.tableName = tableName
    self.rowID = row["id"] ?? .null
    self.before = row["before"]?.dataValue
    self.after = row["after"]?.dataValue
  }
}
