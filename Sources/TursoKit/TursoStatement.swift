import CTursoSDK
import Foundation

public enum TursoStepResult: Sendable, Equatable {
  case row
  case done
  case needsIO
  case busy
}

public final class TursoStatement: @unchecked Sendable {
  let handle: OpaquePointer
  private var finalized = false
  private let asyncIO: Bool

  init(connection: OpaquePointer, sql: String, asyncIO: Bool) throws {
    self.asyncIO = asyncIO
    var stmt: OpaquePointer?
    var err: UnsafePointer<CChar>?
    let st = sql.withCString { csql in
      turso_connection_prepare_single(connection, csql, &stmt, &err)
    }
    try TursoError.check(st, error: err)
    guard let stmt else {
      throw TursoError(code: Int32(TURSO_ERROR.rawValue), message: "prepare returned null")
    }
    self.handle = stmt
  }

  deinit {
    finalize()
  }

  public func finalize() {
    guard !finalized else { return }
    finalized = true
    var err: UnsafePointer<CChar>?
    var st = turso_statement_finalize(handle, &err)
    while st == TURSO_IO {
      _ = turso_statement_run_io(handle, &err)
      st = turso_statement_finalize(handle, &err)
    }
    turso_statement_deinit(handle)
  }

  public func reset() throws {
    var err: UnsafePointer<CChar>?
    var st = turso_statement_reset(handle, &err)
    while st == TURSO_IO {
      try TursoError.check(turso_statement_run_io(handle, &err), error: err)
      st = turso_statement_reset(handle, &err)
    }
    try TursoError.check(st, error: err, allowed: [TURSO_OK, TURSO_DONE])
  }

  /// Clearing bindings is not exposed by the current sdk-kit C ABI.
  ///
  /// This method previously returned success without changing the statement,
  /// which could cause a reused statement to execute with stale values. Callers
  /// must currently finalize and prepare a new statement instead.
  public func clearBindings() throws {
    throw TursoError(
      code: Int32(TURSO_MISUSE.rawValue),
      message: "clearBindings is unavailable in the current sdk-kit ABI; prepare a new statement"
    )
  }

  public func bind(_ value: TursoValue, at index: Int) throws {
    let pos = index
    let st: turso_status_code_t
    switch value {
    case .null:
      st = turso_statement_bind_positional_null(handle, pos)
    case .integer(let v):
      st = turso_statement_bind_positional_int(handle, pos, v)
    case .double(let v):
      st = turso_statement_bind_positional_double(handle, pos, v)
    case .text(let s):
      st = s.withCString { ptr in
        turso_statement_bind_positional_text(handle, pos, ptr, s.utf8.count)
      }
    case .blob(let data):
      st = data.withUnsafeBytes { buffer in
        let base = buffer.bindMemory(to: CChar.self).baseAddress
        return turso_statement_bind_positional_blob(
          handle,
          pos,
          base,
          buffer.count
        )
      }
    }
    try TursoError.check(st, error: nil)
  }

  public func bind(_ values: [TursoValue]) throws {
    for (offset, value) in values.enumerated() {
      try bind(value, at: offset + 1)
    }
  }

  /// Single native step without driving IO (official `TURSO_IO` surface).
  public func stepOnce() throws -> TursoStepResult {
    var err: UnsafePointer<CChar>?
    let st = turso_statement_step(handle, &err)
    switch st {
    case TURSO_ROW: return .row
    case TURSO_DONE: return .done
    case TURSO_IO: return .needsIO
    case TURSO_BUSY: return .busy
    default:
      throw TursoError.from(status: st, message: err.map { String(cString: $0) })
    }
  }

  /// Drive one IO iteration after ``TursoStepResult/needsIO``.
  public func runIOOnce() throws {
    var err: UnsafePointer<CChar>?
    let st = turso_statement_run_io(handle, &err)
    try TursoError.check(st, error: err)
  }

  /// Steps until row/done, driving IO synchronously (no Swift suspension).
  @discardableResult
  public func step() throws -> Bool {
    while true {
      switch try stepOnce() {
      case .row: return true
      case .done: return false
      case .needsIO:
        try runIOOnce()
      case .busy:
        throw TursoError.busy
      }
    }
  }

  /// Cooperative step: yields to the Swift concurrency runtime between IO waits.
  @discardableResult
  public func stepAsync() async throws -> Bool {
    while true {
      switch try stepOnce() {
      case .row: return true
      case .done: return false
      case .needsIO:
        try runIOOnce()
        await Task.yield()
      case .busy:
        throw TursoError.busy
      }
    }
  }

  public var columnCount: Int {
    Int(turso_statement_column_count(handle))
  }

  public func columnName(at index: Int) -> String {
    guard let name = turso_statement_column_name(handle, index) else { return "" }
    return String(cString: name)
  }

  public func value(at index: Int) -> TursoValue {
    TursoValue.column(at: index, statement: handle)
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

  public var changeCount: Int {
    Int(turso_statement_n_change(handle))
  }
}
