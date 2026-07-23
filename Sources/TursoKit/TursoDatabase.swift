import CTursoSDK
import Foundation

/// A Turso Database file on disk (official sdk-kit C ABI).
///
/// Open options use `turso_database_config_t`:
/// `experimental_features`, encryption fields, `async_io`.
public final actor TursoDatabase {
  private final class WeakConnection {
    weak var value: TursoConnection?

    init(_ value: TursoConnection) {
      self.value = value
    }
  }

  public nonisolated let url: URL
  public nonisolated let openOptions: TursoOpenOptions
  private var connections: [ObjectIdentifier: WeakConnection] = [:]
  private var databaseHandle: OpaquePointer?
  private var opened = false
  private var closed = false

  public init(url: URL, openOptions: TursoOpenOptions = TursoOpenOptions()) {
    self.url = url
    self.openOptions = openOptions
  }

  /// Closes every child connection before releasing the native database handle.
  /// Safe to call repeatedly.
  public func close() async {
    guard !closed else { return }
    closed = true
    let openConnections = connections.values.compactMap(\.value)
    connections.removeAll()
    for connection in openConnections {
      await connection.close()
    }
    let handle = databaseHandle
    databaseHandle = nil
    opened = false
    if let handle {
      turso_database_deinit(handle)
    }
  }

  /// Opens (or creates) the database file and returns a connection.
  public func connect(enableCDC: Bool = false) async throws -> TursoConnection {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    try ensureOpened()

    guard let databaseHandle else {
      throw TursoError(code: Int32(TURSO_MISUSE.rawValue), message: "Database handle missing")
    }

    let connectionOut = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
    defer { connectionOut.deallocate() }
    connectionOut.pointee = nil
    var err: UnsafePointer<CChar>?
    let st = turso_database_connect(databaseHandle, connectionOut, &err)
    try TursoError.check(st, error: err)
    guard let conn = connectionOut.pointee else {
      throw TursoError(code: Int32(TURSO_ERROR.rawValue), message: "connect returned null")
    }

    // Disconnect the C handle from the database actor's region so it can be
    // consumed by the new actor-isolated connection.
    let raw = unsafeBitCast(conn, to: UInt.self)
    let handle = OpaquePointer(bitPattern: raw)!
    let connection = TursoConnection(
      database: self,
      handle: handle,
      asyncIO: openOptions.asyncIO
    )
    if enableCDC {
      try await connection.enableCaptureDataChanges(mode: .full)
    }

    // Compact stale weak registrations before adding a new one.
    connections = connections.filter { $0.value.value != nil }
    connections[ObjectIdentifier(connection)] = WeakConnection(connection)
    return connection
  }

  private func ensureOpened() throws {
    guard !closed else {
      throw TursoError(code: Int32(TURSO_MISUSE.rawValue), message: "Database is closed")
    }
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
