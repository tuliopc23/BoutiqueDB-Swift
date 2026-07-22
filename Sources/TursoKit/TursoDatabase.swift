import CTursoSDK
import Foundation

/// A Turso Database file on disk (official sdk-kit C ABI).
///
/// Open options use `turso_database_config_t`:
/// `experimental_features`, encryption fields, `async_io`.
public final class TursoDatabase: @unchecked Sendable {
  public let url: URL
  public let openOptions: TursoOpenOptions
  private let lock = NSLock()
  private var connections: [ObjectIdentifier: TursoConnection] = [:]
  private var databaseHandle: OpaquePointer?
  private var opened = false

  public init(url: URL, openOptions: TursoOpenOptions = TursoOpenOptions()) {
    self.url = url
    self.openOptions = openOptions
  }

  deinit {
    if let databaseHandle {
      turso_database_deinit(databaseHandle)
    }
  }

  /// Opens (or creates) the database file and returns a connection.
  public func connect(enableCDC: Bool = false) throws -> TursoConnection {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    try ensureOpened()

    guard let databaseHandle else {
      throw TursoError(code: Int32(TURSO_MISUSE.rawValue), message: "Database handle missing")
    }

    var conn: OpaquePointer?
    var err: UnsafePointer<CChar>?
    let st = turso_database_connect(databaseHandle, &conn, &err)
    try TursoError.check(st, error: err)
    guard let conn else {
      throw TursoError(code: Int32(TURSO_ERROR.rawValue), message: "connect returned null")
    }

    let connection = TursoConnection(
      database: self,
      handle: conn,
      asyncIO: openOptions.asyncIO
    )
    if enableCDC {
      try connection.enableCaptureDataChanges(mode: .full)
    }

    lock.lock()
    connections[ObjectIdentifier(connection)] = connection
    lock.unlock()
    return connection
  }

  private func ensureOpened() throws {
    lock.lock()
    defer { lock.unlock() }
    if opened { return }

    let path = url.path
    let featuresCSV = openOptions.experimentalFeaturesCSV
    let vfs = openOptions.vfs
    let cipher = openOptions.encryptionCipher
    let hexkey = openOptions.encryptionHexKey
    let asyncIO = openOptions.asyncIO

    try path.withCString { pathPtr in
      try withOptionalCString(featuresCSV) { featPtr in
        try withOptionalCString(vfs) { vfsPtr in
          try withOptionalCString(cipher) { cipherPtr in
            try withOptionalCString(hexkey) { hexPtr in
              var cfg = turso_database_config_t(
                async_io: asyncIO ? 1 : 0,
                path: pathPtr,
                experimental_features: featPtr,
                vfs: vfsPtr,
                encryption_cipher: cipherPtr,
                encryption_hexkey: hexPtr
              )
              var db: OpaquePointer?
              var err: UnsafePointer<CChar>?
              var st = turso_database_new(&cfg, &db, &err)
              try TursoError.check(st, error: err)
              guard let db else {
                throw TursoError(
                  code: Int32(TURSO_ERROR.rawValue),
                  message: "database_new returned null"
                )
              }
              st = turso_database_open(db, &err)
              while st == TURSO_IO {
                st = turso_database_open(db, &err)
              }
              try TursoError.check(st, error: err)
              self.databaseHandle = db
              self.opened = true
            }
          }
        }
      }
    }
  }

  func unregister(_ connection: TursoConnection) {
    lock.lock()
    connections.removeValue(forKey: ObjectIdentifier(connection))
    lock.unlock()
  }

  public static func applicationSupportURL(filename: String = "app.db") throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let dir = base.appendingPathComponent("BoutiqueDB", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(filename)
  }
}

private func withOptionalCString<T>(
  _ string: String?,
  _ body: (UnsafePointer<CChar>?) throws -> T
) rethrows -> T {
  if let string {
    return try string.withCString { try body($0) }
  }
  return try body(nil)
}
