import Foundation
import Observation
import StructuredQueries
import StructuredQueriesTurso
import TursoKit
import TursoObservation

/// A high-level, ``@Observable``-friendly container for a local Turso database
/// with optional CloudKit sync.
///
/// - Important: I/O runs on ``DatabaseActor``; this type stays `@MainActor` (BD-014).
/// - Important: Prefer ``read`` / ``write`` / ``writeConcurrent`` — do not hold a
///   long-lived raw connection outside those scopes.
/// - Important: CDC capture is per-connection; the concurrent MVCC writer also
///   enables CDC when the primary does, so changes land in shared `turso_cdc`
///   and drain/LiveQuery stay correct (BD-005 dual-handle design).
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
  /// When true, ``writeConcurrent`` opens/uses a dedicated MVCC connection (BD-005).
  private let wantsConcurrentWrites: Bool
  private let enableCDC: Bool
  /// Optional second connection with MVCC for ``writeConcurrent`` (opened lazily).
  private var concurrentActor: DatabaseActor?
  private var concurrentConnection: TursoConnection?
  /// Whether the concurrent writer connection has CDC capture enabled.
  private var concurrentCapturesCDC = false
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
  ///   - concurrentWrites: When `true`, ``writeConcurrent`` uses a **second** MVCC
  ///     connection so CDC observation stays on the primary handle (BD-005).
  ///   - openOptions: Official Turso open flags (`experimental_features`, encryption, …).
  ///     Defaults to ``TursoOpenOptions/tursoEnhanced`` (views + index_method + safe DDL flags).
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

    self.concurrentConnection = nil
    self.concurrentActor = nil
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
  /// (e.g. attaching ``TursoCKSyncEngine``). Prefer ``write`` / ``read``.
  public var unsafeConnection: TursoConnection { connection }

  /// Opens the concurrent writer on first use (after schema exists).
  ///
  /// **Contract (A-001):** Concurrent commits must appear in `turso_cdc` when
  /// primary CDC is enabled, so LiveQuery + CloudKit drain stay correct.
  ///
  /// Turso requires MVCC for `BEGIN CONCURRENT`, but CDC capture is often
  /// incompatible on the same handle. Strategy:
  /// 1. Try dedicated MVCC writer **with** CDC (best case: true concurrent + capture).
  /// 2. If CDC cannot attach after MVCC, **close** that writer and use the
  ///    primary CDC connection with busy-retry `BEGIN IMMEDIATE` writes instead
  ///    of true concurrent (still correct for sync; no silent data loss).
  private func ensureConcurrentActor() throws -> DatabaseActor {
    if let concurrentActor { return concurrentActor }
    guard wantsConcurrentWrites else {
      throw BoutiqueError.featureUnavailable(
        "writeConcurrent requires concurrentWrites: true at init"
      )
    }
    if !enableCDC {
      // No CDC: true MVCC concurrent on primary (or dedicated handle).
      return databaseActor
    }

    let writer = try database.connect(enableCDC: false)
    try writer.execute("PRAGMA journal_mode = mvcc")
    do {
      try writer.enableCaptureDataChanges(mode: .full)
      // Best case: concurrent + capture on dedicated handle.
      concurrentCapturesCDC = true
      let actor = DatabaseActor(connection: writer)
      concurrentConnection = writer
      concurrentActor = actor
      return actor
    } catch {
      // Engine rejected CDC on MVCC handle — do not keep a silent non-capturing writer.
      writer.close()
      concurrentCapturesCDC = false
      // Fall back to primary CDC connection (busy-retry IMMEDIATE, not BEGIN CONCURRENT).
      concurrentActor = databaseActor
      concurrentConnection = nil
      return databaseActor
    }
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
    concurrentConnection?.close()
    concurrentConnection = nil
    concurrentActor = nil
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
  /// When the engine supports CDC+MVCC on a dedicated handle, uses
  /// `BEGIN CONCURRENT`. Otherwise (common with CDC enabled) uses busy-retry
  /// `BEGIN IMMEDIATE` on the primary CDC connection so changes are always
  /// captured for observation and sync — never silent.
  @discardableResult
  public func writeConcurrent<T: Sendable>(
    maxAttempts: Int = 8,
    _ body: @Sendable (inout BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    let actor = try ensureConcurrentActor()
    let value: T
    if concurrentCapturesCDC || !enableCDC {
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

  /// Low-level MVCC begin on the concurrent writer connection (BD-005 dual handle).
  ///
  /// Requires a real MVCC writer. When CDC forces the primary busy-retry path,
  /// prefer ``writeConcurrent`` instead.
  public func beginConcurrent() async throws {
    let actor = try ensureConcurrentActor()
    if enableCDC && !concurrentCapturesCDC {
      throw BoutiqueError.featureUnavailable(
        "beginConcurrent requires MVCC on the writer; with CDC enabled the engine fell back to busy-retry IMMEDIATE — use writeConcurrent instead"
      )
    }
    try await actor.beginConcurrent()
  }

  /// Low-level MVCC commit on the concurrent writer connection.
  public func commitConcurrent() async throws {
    let actor = try ensureConcurrentActor()
    try await actor.commitConcurrent()
    notifyLocalCommit()
  }

  /// Low-level MVCC rollback on the concurrent writer connection.
  public func rollbackConcurrent() async throws {
    let actor = try ensureConcurrentActor()
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
