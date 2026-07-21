import CTursoSQLite3
import Foundation

/// A Turso Database file on disk. Open one connection for app CRUD and
/// (optionally) a dedicated non-MVCC connection for CDC + CloudKit sync.
public final class TursoDatabase: @unchecked Sendable {
  public let url: URL
  private let lock = NSLock()
  private var connections: [ObjectIdentifier: TursoConnection] = [:]

  public init(url: URL) {
    self.url = url
  }

  /// Opens (or creates) the database file and returns a connection.
  public func connect(enableCDC: Bool = false) throws -> TursoConnection {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var db: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    let rc = sqlite3_open_v2(url.path, &db, flags, nil)
    guard rc == SQLITE_OK, let db else {
      let message = db.flatMap { sqlite3_errmsg($0).map(String.init(cString:)) } ?? "open failed"
      if let db { sqlite3_close(db) }
      throw TursoError(code: rc, message: message)
    }

    let connection = TursoConnection(database: self, handle: db)
    if enableCDC {
      try connection.enableCaptureDataChanges(mode: .full)
    }

    lock.lock()
    connections[ObjectIdentifier(connection)] = connection
    lock.unlock()
    return connection
  }

  func unregister(_ connection: TursoConnection) {
    lock.lock()
    connections.removeValue(forKey: ObjectIdentifier(connection))
    lock.unlock()
  }

  /// Convenience: Application Support directory + filename.
  public static func applicationSupportURL(filename: String = "app.db") throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let dir = base.appendingPathComponent("TursoCloudKit", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(filename)
  }
}
