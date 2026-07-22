import CloudKit
import Foundation
import TursoCKSync
import TursoKit

/// Higher-level CloudKit sync façade paired with ``BoutiqueDB``.
///
/// Wraps ``CloudKitSyncAdapter`` (the default ``SyncAdapter``) so apps can
/// observe ``SyncStatus`` and drain CDC without talking to CKSyncEngine directly.
///
/// Prefer ``attach(to:automaticallyDrain:)`` so local ``BoutiqueDB/write`` commits
/// auto-drain without the app remembering to call ``drainCDC``.
@MainActor
public final class BoutiqueDBSyncEngine: Sendable {
  public let adapter: CloudKitSyncAdapter
  public var engine: TursoCKSyncEngine { adapter.engine }

  public init(
    connection: TursoConnection,
    containerIdentifier: String? = nil,
    syncedTables: [SyncedTable],
    conflictPolicy: ConflictPolicy = .serverWins,
    maxBatchSize: Int = 250,
    enablesCloudKit: Bool = true
  ) throws {
    let configuration = TursoCKSyncConfiguration(
      containerIdentifier: containerIdentifier,
      syncedTables: syncedTables,
      conflictPolicy: conflictPolicy,
      maxBatchSize: maxBatchSize,
      drainCDCLimit: 500,
      enablesCloudKit: enablesCloudKit
    )
    self.adapter = try CloudKitSyncAdapter(
      connection: connection,
      configuration: configuration
    )
  }

  /// Builds a sync engine from the database's primary connection.
  public convenience init(
    db: BoutiqueDB,
    containerIdentifier: String? = nil,
    syncedTables: [SyncedTable],
    conflictPolicy: ConflictPolicy = .serverWins,
    maxBatchSize: Int = 250,
    enablesCloudKit: Bool = true
  ) throws {
    try self.init(
      connection: db.unsafeConnection,
      containerIdentifier: containerIdentifier,
      syncedTables: syncedTables,
      conflictPolicy: conflictPolicy,
      maxBatchSize: maxBatchSize,
      enablesCloudKit: enablesCloudKit
    )
  }

  public init(adapter: CloudKitSyncAdapter) {
    self.adapter = adapter
  }

  /// Registers auto-drain on ``BoutiqueDB/onLocalCommit`` after each successful write.
  public func attach(to db: BoutiqueDB, automaticallyDrain: Bool = true) {
    guard automaticallyDrain else {
      db.onLocalCommit = nil
      return
    }
    db.onLocalCommit = { [weak self] in
      guard let self else { return }
      _ = try self.engine.drainCDC()
    }
  }

  public func start(automaticallySync: Bool = true) throws {
    try engine.start(automaticallySync: automaticallySync)
  }

  public func syncStatus() -> AsyncStream<SyncStatus> {
    adapter.syncStatus()
  }

  @discardableResult
  public func drainCDC(limit: Int = 500) throws -> Int {
    try engine.drainCDC(limit: limit)
  }

  @discardableResult
  public func drainLocalChanges() async throws -> Int {
    try await adapter.drainLocalChanges()
  }

  @discardableResult
  public func performLocalWrite(_ body: () throws -> Void) throws -> Int {
    try engine.performLocalWrite(body)
  }
}
