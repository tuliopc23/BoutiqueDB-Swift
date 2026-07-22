import CTursoSDK
import Foundation

public enum CDCCaptureMode: String, Sendable {
  case off
  case id
  case before
  case after
  case full
}

/// A single connection to a Turso Database (sdk-kit C ABI).
///
/// - Important: Do not enable `journal_mode=mvcc` on a connection that also
///   enables CDC (`PRAGMA capture_data_changes_conn`). They are mutually exclusive.
public final class TursoConnection: @unchecked Sendable {
  public private(set) weak var database: TursoDatabase?
  let handle: OpaquePointer
  private let asyncIO: Bool
  private let lock = NSRecursiveLock()
  private var closed = false
  private var lastChanges: Int = 0

  private var _isSynchronizing: Bool = false

  public var isApplyingRemoteChanges: Bool {
    withLockUnchecked { _isSynchronizing }
  }

  public var isSynchronizing: Bool {
    get { isApplyingRemoteChanges }
    set { withLockUnchecked { _isSynchronizing = newValue } }
  }

  public func withSynchronizingFlag<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    _isSynchronizing = true
    lock.unlock()
    defer {
      lock.lock()
      _isSynchronizing = false
      lock.unlock()
    }
    return try body()
  }

  /// Whether this connection was opened with sdk-kit `async_io` (cooperative IO).
  public var usesAsyncIO: Bool { asyncIO }

  init(database: TursoDatabase, handle: OpaquePointer, asyncIO: Bool) {
    self.database = database
    self.handle = handle
    self.asyncIO = asyncIO
  }

  private func withLockUnchecked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
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
    var err: UnsafePointer<CChar>?
    _ = turso_connection_close(handle, &err)
    turso_connection_deinit(handle)
  }

  // MARK: - Execute / Query

  public func execute(_ sql: String, _ bindings: [TursoValue] = []) throws {
    try withLock {
      try executeUnlocked(sql, bindings)
    }
  }

  @discardableResult
  public func executeUpdate(_ sql: String, _ bindings: [TursoValue] = []) throws -> Int {
    try withLock {
      try executeUnlocked(sql, bindings)
      return lastChanges
    }
  }

  public func query(_ sql: String, _ bindings: [TursoValue] = []) throws -> [[String: TursoValue]] {
    try withLock {
      try queryUnlocked(sql, bindings)
    }
  }

  public func queryOne(_ sql: String, _ bindings: [TursoValue] = []) throws -> [String: TursoValue]? {
    try query(sql, bindings).first
  }

  public func prepare(_ sql: String) throws -> TursoStatement {
    try withLock {
      try TursoStatement(connection: handle, sql: sql, asyncIO: asyncIO)
    }
  }

  public func withPreparedStatement<T>(
    _ sql: String,
    _ body: (TursoStatement) throws -> T
  ) throws -> T {
    try withLock {
      let statement = try TursoStatement(connection: handle, sql: sql, asyncIO: asyncIO)
      defer { statement.finalize() }
      return try body(statement)
    }
  }

  public func lastInsertRowID() -> Int64 {
    turso_connection_last_insert_rowid(handle)
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

  /// MVCC concurrent transaction (`BEGIN CONCURRENT`).
  public func writeConcurrent<T>(_ body: () throws -> T) throws -> T {
    try withLock {
      try executeUnlocked("BEGIN CONCURRENT")
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
      throw TursoError(code: Int32(TURSO_MISUSE.rawValue), message: "Connection is closed")
    }
    return try body()
  }

  func executeUnlocked(_ sql: String, _ bindings: [TursoValue] = []) throws {
    let statement = try TursoStatement(connection: handle, sql: sql, asyncIO: asyncIO)
    defer { statement.finalize() }
    try statement.bind(bindings)
    while try statement.step() {}
    lastChanges = statement.changeCount
  }

  func queryUnlocked(_ sql: String, _ bindings: [TursoValue] = []) throws -> [[String: TursoValue]] {
    let statement = try TursoStatement(connection: handle, sql: sql, asyncIO: asyncIO)
    defer { statement.finalize() }
    try statement.bind(bindings)
    var rows: [[String: TursoValue]] = []
    while try statement.step() {
      rows.append(statement.namedRow())
    }
    return rows
  }

  // MARK: - Cooperative async (official `async_io` + TURSO_IO)

  /// Async execute: drives ``TURSO_IO`` with `await Task.yield()` between IO ticks.
  public func executeAsync(_ sql: String, _ bindings: [TursoValue] = []) async throws {
    try await withLockAsync {
      try await executeUnlockedAsync(sql, bindings)
    }
  }

  public func queryAsync(
    _ sql: String,
    _ bindings: [TursoValue] = []
  ) async throws -> [[String: TursoValue]] {
    try await withLockAsync {
      try await queryUnlockedAsync(sql, bindings)
    }
  }

  public func writeAsync<T: Sendable>(
    _ body: @Sendable () async throws -> T
  ) async throws -> T {
    try await withLockAsync {
      try await executeUnlockedAsync("BEGIN IMMEDIATE")
      do {
        let value = try await body()
        try await executeUnlockedAsync("COMMIT")
        return value
      } catch {
        try? await executeUnlockedAsync("ROLLBACK")
        throw error
      }
    }
  }

  public func readAsync<T: Sendable>(
    _ body: @Sendable () async throws -> T
  ) async throws -> T {
    try await withLockAsync {
      try await executeUnlockedAsync("BEGIN")
      do {
        let value = try await body()
        try await executeUnlockedAsync("COMMIT")
        return value
      } catch {
        try? await executeUnlockedAsync("ROLLBACK")
        throw error
      }
    }
  }

  public func writeConcurrentAsync<T: Sendable>(
    _ body: @Sendable () async throws -> T
  ) async throws -> T {
    try await withLockAsync {
      try await executeUnlockedAsync("BEGIN CONCURRENT")
      do {
        let value = try await body()
        try await executeUnlockedAsync("COMMIT")
        return value
      } catch {
        try? await executeUnlockedAsync("ROLLBACK")
        throw error
      }
    }
  }

  private func withLockAsync<T>(_ body: () async throws -> T) async throws -> T {
    // NSLock is not async-safe; callers (DatabaseActor) provide exclusivity.
    // Use a nonisolated snapshot of `closed` without lock (actor serializes BoutiqueDB path).
    guard !closed else {
      throw TursoError(code: Int32(TURSO_MISUSE.rawValue), message: "Connection is closed")
    }
    return try await body()
  }

  func executeUnlockedAsync(_ sql: String, _ bindings: [TursoValue] = []) async throws {
    let statement = try TursoStatement(connection: handle, sql: sql, asyncIO: asyncIO)
    defer { statement.finalize() }
    try statement.bind(bindings)
    while try await statement.stepAsync() {}
    lastChanges = statement.changeCount
  }

  func queryUnlockedAsync(
    _ sql: String,
    _ bindings: [TursoValue] = []
  ) async throws -> [[String: TursoValue]] {
    let statement = try TursoStatement(connection: handle, sql: sql, asyncIO: asyncIO)
    defer { statement.finalize() }
    try statement.bind(bindings)
    var rows: [[String: TursoValue]] = []
    while try await statement.stepAsync() {
      rows.append(statement.namedRow())
    }
    return rows
  }
}

// MARK: - CDC model

public struct CDCChange: Sendable, Equatable {
  public var changeID: Int64
  public var changeTime: Int64
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
