import CloudKit
import Foundation
import TursoKit

/// Pluggable multi-device sync surface for BoutiqueDB.
///
/// Default implementation: ``CloudKitSyncAdapter``. A future Turso Cloud adapter
/// can conform without changing app-facing APIs.
public protocol SyncAdapter: AnyObject, Sendable {
  /// Begin observing / pushing changes.
  func start() async throws

  /// Stop sync (best-effort).
  func stop() async

  /// Live sync status for SwiftUI (no polling).
  func syncStatus() -> AsyncStream<SyncStatus>

  /// Drain local CDC into pending outbound changes. Returns number of pending ops enqueued.
  @discardableResult
  func drainLocalChanges() async throws -> Int

  /// Apply remote records (tests / custom transports).
  func applyRemoteChanges(_ changes: [RemoteChange]) async throws
}

/// High-level sync lifecycle for UI and diagnostics.
public enum SyncStatus: Sendable, Equatable {
  case idle
  case syncing
  case failed(String)
  case needsAuthentication
  case accountChanged
}

/// Transport-agnostic remote mutation used by ``SyncAdapter/applyRemoteChanges(_:)``.
public enum RemoteChange: Sendable {
  case upsert(CKRecord)
  case delete(CKRecord.ID)
}

/// Default CloudKit-backed ``SyncAdapter``.
public final class CloudKitSyncAdapter: SyncAdapter, @unchecked Sendable {
  public let engine: TursoCKSyncEngine

  private let statusLock = NSLock()
  private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
  private var currentStatus: SyncStatus = .idle

  public init(engine: TursoCKSyncEngine) {
    self.engine = engine
    engine.statusSink = { [weak self] status in
      self?.publish(status)
    }
  }

  public convenience init(
    connection: TursoConnection,
    configuration: TursoCKSyncConfiguration,
    container: CKContainer? = nil
  ) throws {
    let engine = try TursoCKSyncEngine(
      connection: connection,
      configuration: configuration,
      container: container
    )
    self.init(engine: engine)
  }

  public func start() async throws {
    publish(.syncing)
    do {
      try engine.start(automaticallySync: engine.configuration.enablesCloudKit)
      try await engine.detectAccountIdentityChangeIfNeeded()
      publish(.idle)
    } catch {
      publish(.failed(error.localizedDescription))
      throw error
    }
  }

  public func stop() async {
    engine.stop()
    publish(.idle)
  }

  public func syncStatus() -> AsyncStream<SyncStatus> {
    AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
      let id = UUID()
      statusLock.lock()
      statusContinuations[id] = continuation
      continuation.yield(currentStatus)
      statusLock.unlock()
      continuation.onTermination = { [weak self] _ in
        self?.statusLock.lock()
        self?.statusContinuations[id] = nil
        self?.statusLock.unlock()
      }
    }
  }

  @discardableResult
  public func drainLocalChanges() async throws -> Int {
    publish(.syncing)
    do {
      let count = try engine.drainCDC(limit: engine.configuration.drainCDCLimit)
      publish(.idle)
      return count
    } catch {
      publish(.failed(error.localizedDescription))
      throw error
    }
  }

  public func applyRemoteChanges(_ changes: [RemoteChange]) async throws {
    publish(.syncing)
    do {
      for change in changes {
        switch change {
        case .upsert(let record):
          try engine.applyRemoteRecord(record)
        case .delete(let id):
          try engine.applyRemoteDeletion(recordID: id)
        }
      }
      publish(.idle)
    } catch {
      publish(.failed(error.localizedDescription))
      throw error
    }
  }

  private func publish(_ status: SyncStatus) {
    statusLock.lock()
    currentStatus = status
    let conts = statusContinuations.values
    statusLock.unlock()
    for cont in conts {
      cont.yield(status)
    }
  }
}
