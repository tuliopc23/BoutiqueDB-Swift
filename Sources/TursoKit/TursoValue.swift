import CTursoSDK
import Foundation

/// A value that can be bound to or read from a Turso statement.
public enum TursoValue: Sendable, Equatable {
  case null
  case integer(Int64)
  case double(Double)
  case text(String)
  case blob(Data)

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  public var int64Value: Int64? {
    switch self {
    case .integer(let v): return v
    case .double(let v): return Int64(v)
    case .text(let s): return Int64(s)
    default: return nil
    }
  }

  public var doubleValue: Double? {
    switch self {
    case .double(let v): return v
    case .integer(let v): return Double(v)
    case .text(let s): return Double(s)
    default: return nil
    }
  }

  public var stringValue: String? {
    switch self {
    case .text(let v): return v
    case .integer(let v): return String(v)
    case .double(let v): return String(v)
    case .blob(let d): return String(data: d, encoding: .utf8)
    case .null: return nil
    }
  }

  public var dataValue: Data? {
    switch self {
    case .blob(let d): return d
    case .text(let s): return Data(s.utf8)
    case .null: return nil
    default: return nil
    }
  }
}

extension TursoValue {
  static func column(at index: Int, statement: OpaquePointer) -> TursoValue {
    let kind = turso_statement_row_value_kind(statement, index)
    switch kind {
    case TURSO_TYPE_NULL:
      return .null
    case TURSO_TYPE_INTEGER:
      return .integer(turso_statement_row_value_int(statement, index))
    case TURSO_TYPE_REAL:
      return .double(turso_statement_row_value_double(statement, index))
    case TURSO_TYPE_TEXT:
      guard let ptr = turso_statement_row_value_bytes_ptr(statement, index) else { return .null }
      let count = Int(turso_statement_row_value_bytes_count(statement, index))
      guard count > 0 else { return .text("") }
      let data = Data(bytes: ptr, count: count)
      return .text(String(data: data, encoding: .utf8) ?? "")
    case TURSO_TYPE_BLOB:
      guard let ptr = turso_statement_row_value_bytes_ptr(statement, index) else {
        return .blob(Data())
      }
      let count = Int(turso_statement_row_value_bytes_count(statement, index))
      guard count > 0 else { return .blob(Data()) }
      return .blob(Data(bytes: ptr, count: count))
    default:
      return .null
    }
  }
}
