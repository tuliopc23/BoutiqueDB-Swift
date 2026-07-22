import Foundation
import Observation
import StructuredQueries
import StructuredQueriesTurso
import TursoKit
import TursoObservation

/// A high-level, `@Observable`-friendly container for a local Turso database
/// with optional CloudKit sync.
///
/// - Important: I/O runs on `DatabaseActor`; this type stays `@MainActor` (BD-014).
/// - Important: Prefer ``read(_:)`` / ``write(_:)`` /
///   ``writeConcurrent(maxAttempts:_:)`` — do not hold a
///   long-lived raw connection outside those scopes.
/// - Important: CDC capture and MVCC cannot safely be enabled on separate
///   handles after a database is active. With CDC enabled,
///   ``writeConcurrent(maxAttempts:_:)``
///   therefore uses retrying `BEGIN IMMEDIATE` writes on the primary handle so
///   changes always land in `turso_cdc` (BD-005 correctness fallback).
@MainActor
public final class BoutiqueDB: Sendable {
  public let url: URL
  /// Raw primary connection. Prefer actor-mediated APIs; use only for advanced
  /// sync attachment and tests. Not a concurrency-safe public I/O surface.
  package let connection: TursoConnection
  public let store: TursoStore
  /// Probed Turso feature flags (FTS/vector/MV/encryption, etc.).
  public let capabilities: TursoCapabilities
  private let database: TursoDatabase
  private let databaseActor: DatabaseActor
  /// When true, ``writeConcurrent`` enables the safest supported contention path.
  private let wantsConcurrentWrites: Bool
  private let enableCDC: Bool
  /// Invoked after successful local commits (write / writeConcurrent / commitConcurrent).
  /// Attach a sync drain here (e.g. `BoutiqueDBSyncEngine` auto-drain).
  public var onLocalCommit: (@MainActor () throws -> Void)?
  private var postCommitObservers: [UUID: @MainActor () throws -> Void] = [:]
  /// Most recent observer failure. The local transaction has already committed
  /// when this is set, so the error is reported without pretending to roll it back.
  public private(set) var lastPostCommitError: BoutiqueError?
  private var closed = false

  /// Opens (or creates) a database file at `url` via the official sdk-kit C ABI.
  ///
  /// - Parameters:
  ///   - url: Database file URL.
  ///   - startListening: When `true` (default), starts the cooperative CDC listener.
  ///   - enableCDC: When `true` (default), enables CDC on the primary connection.
  ///   - concurrentWrites: Enables ``writeConcurrent(maxAttempts:_:)``. With CDC,
  ///     this is a retrying primary-handle write; without CDC, the primary handle
  ///     uses MVCC.
  ///   - openOptions: Official Turso open flags (`experimental_features`, encryption, …).
  ///     Defaults to `TursoOpenOptions.tursoEnhanced` (views + index_method + safe DDL flags).
  ///   - encryption: Optional engine encryption (maps to official cipher/hexkey + `encryption` token).
  ///   - multiProcess: Multi-process WAL (`multiprocess_wal` token). Requires App Group for extensions.
  public init(
    url: URL,
    startListening: Bool = true,
    enableCDC: Bool = true,
    concurrentWrites: Bool = false,
    openOptions: TursoOpenOptions = .tursoEnhanced,
    encryption: EncryptionConfig? = nil,
    multiProcess: Bool = false
  ) throws {
    var options = openOptions
    if multiProcess {
      options.insert(.multiprocessWAL)
    }
    if let encryption {
      options.insert(.encryption)
      switch encryption {
      case .aegis256(let key):
        options.encryptionCipher = "aegis256"
        options.encryptionHexKey = key.map { String(format: "%02x", $0) }.joined()
      case .aes256gcm(let key):
        options.encryptionCipher = "aes256gcm"
        options.encryptionHexKey = key.map { String(format: "%02x", $0) }.joined()
      }
    }

    self.url = url
    self.enableCDC = enableCDC
    self.wantsConcurrentWrites = concurrentWrites
    self.database = TursoDatabase(url: url, openOptions: options)
    do {
      self.connection = try database.connect(enableCDC: enableCDC)
    } catch {
      // Map open failures for encryption/multiprocess to clear Boutique errors when possible.
      if multiProcess {
        throw BoutiqueError.multiProcessWALUnavailable
      }
      if encryption != nil {
        throw BoutiqueError.encryptionUnavailable
      }
      throw error
    }

    if concurrentWrites && !enableCDC {
      try connection.execute("PRAGMA journal_mode = mvcc")
    }

    self.databaseActor = DatabaseActor(connection: connection)
    self.store = TursoStore(connection: connection)
    self.capabilities = TursoCapabilities.probe(on: connection)
    if startListening {
      self.store.startListening()
    }
  }

  /// Opens the native store from a shared bootstrap configuration.
  /// Use ``open(_:)`` when the configuration contains migrations or schema sync.
  public convenience init(configuration: BoutiqueDBConfiguration) throws {
    try self.init(
      url: configuration.url,
      startListening: configuration.startListening,
      enableCDC: configuration.enableCDC,
      concurrentWrites: configuration.concurrentWrites,
      openOptions: configuration.openOptions,
      encryption: configuration.encryption,
      multiProcess: configuration.multiProcess
    )
  }

  deinit {
    database.close()
  }

  /// Escape hatch for advanced callers that must touch the primary handle
  /// (e.g. attaching `TursoCKSyncEngine`). Prefer ``write(_:)`` / ``read(_:)``.
  public var unsafeConnection: TursoConnection { connection }

  /// Selects the safe contention strategy on first use.
  ///
  /// **Contract (A-001):** Concurrent commits must appear in `turso_cdc` when
  /// primary CDC is enabled, so LiveQuery + CloudKit drain stay correct.
  ///
  /// Turso requires MVCC for `BEGIN CONCURRENT`. Enabling MVCC dynamically on a
  /// second handle after the primary CDC connection is active can invalidate the
  /// engine's page-to-table mapping. Until the engine supports that transition,
  /// CDC databases always use primary-handle busy-retry `BEGIN IMMEDIATE` writes.
  private func ensureConcurrentActor() async throws -> DatabaseActor {
    guard wantsConcurrentWrites else {
      throw BoutiqueError.featureUnavailable(
        "writeConcurrent requires concurrentWrites: true at init"
      )
    }
    // When CDC is disabled, MVCC was enabled on the primary before schema access.
    // When CDC is enabled, this same actor supplies the serialized retry path.
    return databaseActor
  }

  private func notifyLocalCommit() {
    store.invalidate()
    var observers = Array(postCommitObservers.values)
    if let onLocalCommit { observers.append(onLocalCommit) }
    for observer in observers {
      do {
        try observer()
      } catch {
        lastPostCommitError = .postCommitObserverFailed(String(describing: error))
      }
    }
  }

  /// Adds a post-commit observer without replacing existing integrations.
  /// The returned token can be passed to ``removePostCommitObserver(_:)``.
  @discardableResult
  public func addPostCommitObserver(
    _ observer: @escaping @MainActor () throws -> Void
  ) -> UUID {
    let id = UUID()
    postCommitObservers[id] = observer
    return id
  }

  public func removePostCommitObserver(_ id: UUID) {
    postCommitObservers[id] = nil
  }

  /// Stops observation and closes every native connection in dependency order.
  /// Safe to call repeatedly. No database API may be used after closing.
  public func close() {
    guard !closed else { return }
    closed = true
    store.stopListening()
    connection.close()
    database.close()
    postCommitObservers.removeAll()
    onLocalCommit = nil
  }

  /// Backward-compatible alias.
  public convenience init(url: URL, startPolling: Bool) throws {
    try self.init(url: url, startListening: startPolling)
  }

  /// Backward-compatible CDC+MVCC same-handle rejection (single connection).
  public convenience init(
    url: URL,
    startListening: Bool = true,
    enableCDC: Bool,
    enableMVCC: Bool
  ) throws {
    if enableCDC && enableMVCC {
      throw BoutiqueError.cdcMutuallyExclusiveWithMVCC
    }
    try self.init(
      url: url,
      startListening: startListening,
      enableCDC: enableCDC,
      concurrentWrites: enableMVCC
    )
  }

  // MARK: - Async I/O

  public func read<T: Sendable>(
    _ body: @Sendable (BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    try await databaseActor.read(body)
  }

  @discardableResult
  public func write<T: Sendable>(
    _ body: @Sendable (inout BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    let value = try await databaseActor.write(body)
    notifyLocalCommit()
    return value
  }

  @discardableResult
  public func transaction<T: Sendable>(
    _ body: @Sendable (inout BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    try await write(body)
  }

  /// High-contention write with `SQLITE_BUSY` retry/backoff.
  ///
  /// Without CDC this uses `BEGIN CONCURRENT`. With CDC it uses busy-retry
  /// `BEGIN IMMEDIATE` on the primary connection so changes are always captured
  /// for observation and sync, without an unsafe live journal-mode transition.
  @discardableResult
  public func writeConcurrent<T: Sendable>(
    maxAttempts: Int = 8,
    _ body: @Sendable (inout BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    let actor = try await ensureConcurrentActor()
    let value: T
    if !enableCDC {
      value = try await actor.writeConcurrent(
        maxAttempts: maxAttempts,
        baseDelayNanoseconds: 1_000_000,
        body
      )
    } else {
      // Primary CDC path: busy-retry IMMEDIATE (still captured).
      value = try await actor.writeWithBusyRetry(
        maxAttempts: maxAttempts,
        baseDelayNanoseconds: 1_000_000,
        body
      )
    }
    notifyLocalCommit()
    return value
  }

  /// Low-level MVCC begin for databases opened with CDC disabled.
  ///
  /// With CDC enabled, prefer ``writeConcurrent(maxAttempts:_:)`` instead.
  public func beginConcurrent() async throws {
    let actor = try await ensureConcurrentActor()
    if enableCDC {
      throw BoutiqueError.featureUnavailable(
        "beginConcurrent requires CDC to be disabled; use writeConcurrent for the CDC-safe busy-retry path"
      )
    }
    try await actor.beginConcurrent()
  }

  /// Low-level MVCC commit on the concurrent writer connection.
  public func commitConcurrent() async throws {
    let actor = try await ensureConcurrentActor()
    guard !enableCDC else {
      throw BoutiqueError.featureUnavailable(
        "commitConcurrent requires CDC to be disabled; use writeConcurrent for the CDC-safe path"
      )
    }
    try await actor.commitConcurrent()
    notifyLocalCommit()
  }

  /// Low-level MVCC rollback on the concurrent writer connection.
  public func rollbackConcurrent() async throws {
    let actor = try await ensureConcurrentActor()
    guard !enableCDC else {
      throw BoutiqueError.featureUnavailable(
        "rollbackConcurrent requires CDC to be disabled; use writeConcurrent for the CDC-safe path"
      )
    }
    try await actor.rollbackConcurrent()
  }

  public func execute(_ sql: String, _ bindings: [TursoValue] = []) async throws {
    try await write { conn in
      try conn.execute(sql, bindings)
    }
  }

  public func fetchAll<T: Table & Sendable>(
    _ table: T.Type
  ) async throws -> [T.QueryOutput] where T == T.QueryOutput {
    try await read { try $0.fetchAll(table) }
  }

  public func fetchOne<T: PrimaryKeyedTable & Sendable>(
    _ table: T.Type,
    key: T.PrimaryKey
  ) async throws -> T.QueryOutput? where T == T.QueryOutput, T.PrimaryKey: Sendable {
    try await read { try $0.fetchOne(table, key: key) }
  }

  // MARK: - Schema / Turso DDL

  public func create<S: BoutiqueSchema>(_ schema: S.Type) async throws {
    let statements = S.boutiqueCreateStatements
    guard !statements.isEmpty else {
      throw BoutiqueError.featureUnavailable(
        "No boutiqueCreateStatements for \(S.self); apply @BoutiqueTable / @FTSIndex / @VectorIndex / @MaterializedView"
      )
    }
    for sql in statements {
      try requireCapability(for: sql)
    }
    try await write { connection in
      for sql in statements {
        try connection.execute(sql)
      }
    }
  }

  public func createFTSIndex(_ index: FTSIndexDescriptor) async throws {
    guard capabilities.ftsIndex else {
      throw BoutiqueError.featureUnavailable(
        "FTS index method unavailable; enable the sdk-kit index_method feature"
      )
    }
    try await execute(index.ddl)
  }

  public func createVectorIndex(_ index: VectorIndexDescriptor) async throws {
    guard capabilities.vectorIndex else {
      throw BoutiqueError.featureUnavailable(
        "Vector index method unavailable; enable the sdk-kit index_method feature"
      )
    }
    try await execute(index.ddl)
  }

  public func createMaterializedView(_ view: MaterializedViewDescriptor) async throws {
    guard capabilities.materializedViews else {
      throw BoutiqueError.featureUnavailable(
        "Materialized views unavailable; enable the sdk-kit views feature"
      )
    }
    try await execute(view.ddl)
  }

  private func requireCapability(for sql: String) throws {
    let lower = sql.lowercased()
    if lower.contains("using fts"), !capabilities.ftsIndex {
      throw BoutiqueError.featureUnavailable("FTS index method unavailable (BD-002)")
    }
    if lower.contains("using vector"), !capabilities.vectorIndex {
      throw BoutiqueError.featureUnavailable("Vector index method unavailable (BD-002)")
    }
    if lower.contains("materialized view"), !capabilities.materializedViews {
      throw BoutiqueError.featureUnavailable("Materialized views unavailable (BD-003)")
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

/// At-rest encryption configuration (Turso AEGIS/AES-GCM).
public enum EncryptionConfig: Sendable, Equatable {
  case aegis256(key: Data)
  case aes256gcm(key: Data)
}
