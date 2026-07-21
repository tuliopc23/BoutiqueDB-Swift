import CTursoSQLite3
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
  static func column(at index: Int32, statement: OpaquePointer) -> TursoValue {
    switch sqlite3_column_type(statement, index) {
    case SQLITE_NULL:
      return .null
    case SQLITE_INTEGER:
      return .integer(sqlite3_column_int64(statement, index))
    case SQLITE_FLOAT:
      return .double(sqlite3_column_double(statement, index))
    case SQLITE_TEXT:
      guard let cString = sqlite3_column_text(statement, index) else { return .null }
      return .text(String(cString: cString))
    case SQLITE_BLOB:
      let bytes = sqlite3_column_bytes(statement, index)
      guard bytes > 0, let ptr = sqlite3_column_blob(statement, index) else {
        return .blob(Data())
      }
      return .blob(Data(bytes: ptr, count: Int(bytes)))
    default:
      return .null
    }
  }
}
