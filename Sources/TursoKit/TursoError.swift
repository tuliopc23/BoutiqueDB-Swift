import CTursoSQLite3
import Foundation

public struct TursoError: Error, Sendable, Equatable, CustomStringConvertible {
  public var code: Int32
  public var message: String

  public init(code: Int32, message: String) {
    self.code = code
    self.message = message
  }

  public var description: String {
    "TursoError(\(code)): \(message)"
  }

  static func from(db: OpaquePointer?) -> TursoError {
    let code = sqlite3_errcode(db)
    let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "Unknown Turso error"
    return TursoError(code: code, message: message)
  }

  public static let busy = TursoError(code: SQLITE_BUSY, message: "SQLITE_BUSY")
}
