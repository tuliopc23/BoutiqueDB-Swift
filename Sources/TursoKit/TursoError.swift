import CTursoSDK
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

  /// Matches `TURSO_BUSY` from sdk-kit.
  public static let busy = TursoError(
    code: Int32(TURSO_BUSY.rawValue),
    message: "TURSO_BUSY"
  )

  static func from(status: turso_status_code_t, message: String?) -> TursoError {
    TursoError(
      code: Int32(status.rawValue),
      message: message ?? "Turso status \(status.rawValue)"
    )
  }

  static func check(
    _ status: turso_status_code_t,
    error: UnsafePointer<CChar>?,
    allowed: Set<turso_status_code_t> = [TURSO_OK]
  ) throws {
    if allowed.contains(status) { return }
    let msg = error.map { String(cString: $0) }
    throw TursoError.from(status: status, message: msg)
  }
}

/// SQLITE_BUSY-compatible alias used by busy-retry callers (`DatabaseActor`).
public let TURSO_SQLITE_BUSY: Int32 = Int32(TURSO_BUSY.rawValue)
