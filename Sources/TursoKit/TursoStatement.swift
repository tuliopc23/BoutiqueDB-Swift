import CTursoSQLite3
import Foundation

public final class TursoStatement: @unchecked Sendable {
  private let db: OpaquePointer
  let handle: OpaquePointer
  private var finalized = false

  init(db: OpaquePointer, sql: String) throws {
    self.db = db
    var stmt: OpaquePointer?
    let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    guard rc == SQLITE_OK, let stmt else {
      throw TursoError.from(db: db)
    }
    self.handle = stmt
  }

  deinit {
    finalize()
  }

  public func finalize() {
    guard !finalized else { return }
    finalized = true
    _ = sqlite3_finalize(handle)
  }

  public func reset() throws {
    let rc = sqlite3_reset(handle)
    guard rc == SQLITE_OK else { throw TursoError.from(db: db) }
  }

  public func clearBindings() throws {
    let rc = sqlite3_clear_bindings(handle)
    guard rc == SQLITE_OK else { throw TursoError.from(db: db) }
  }

  public func bind(_ value: TursoValue, at index: Int) throws {
    let i = Int32(index)
    let rc: Int32
    switch value {
    case .null:
      rc = sqlite3_bind_null(handle, i)
    case .integer(let v):
      rc = sqlite3_bind_int64(handle, i, v)
    case .double(let v):
      rc = sqlite3_bind_double(handle, i, v)
    case .text(let s):
      rc = sqlite3_bind_text(handle, i, s, -1, turso_sqlite_transient())
    case .blob(let data):
      rc = data.withUnsafeBytes { buffer in
        sqlite3_bind_blob(
          handle,
          i,
          buffer.baseAddress,
          Int32(buffer.count),
          turso_sqlite_transient()
        )
      }
    }
    guard rc == SQLITE_OK else { throw TursoError.from(db: db) }
  }

  public func bind(_ values: [TursoValue]) throws {
    for (offset, value) in values.enumerated() {
      try bind(value, at: offset + 1)
    }
  }

  /// Steps once. Returns `true` if a row is available (`SQLITE_ROW`).
  @discardableResult
  public func step() throws -> Bool {
    let rc = sqlite3_step(handle)
    switch rc {
    case SQLITE_ROW:
      return true
    case SQLITE_DONE:
      return false
    default:
      throw TursoError.from(db: db)
    }
  }

  public var columnCount: Int {
    Int(sqlite3_column_count(handle))
  }

  public func columnName(at index: Int) -> String {
    guard let name = sqlite3_column_name(handle, Int32(index)) else { return "" }
    return String(cString: name)
  }

  public func value(at index: Int) -> TursoValue {
    TursoValue.column(at: Int32(index), statement: handle)
  }

  public func row() -> [TursoValue] {
    (0..<columnCount).map { value(at: $0) }
  }

  public func namedRow() -> [String: TursoValue] {
    var result: [String: TursoValue] = [:]
    for i in 0..<columnCount {
      result[columnName(at: i)] = value(at: i)
    }
    return result
  }
}
