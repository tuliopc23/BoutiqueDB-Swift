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
  func syncStatus() async -> AsyncStream<SyncStatus>

  /// Drain local CDC into pending outbound changes. Returns number of pending ops enqueued.
  @discardableResult
  func drainLocalChanges() async throws -> Int

  /// Requests an immediate remote fetch. Normal automatic scheduling remains enabled.
  func fetchChanges() async throws

  /// Drains local CDC and requests an immediate send.
  func sendChanges() async throws

  /// Performs a user-initiated fetch, local drain, and send cycle.
  func syncChanges() async throws

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

/// Transport-neutral record value. CloudKit conversion stays inside
/// ``CloudKitSyncAdapter`` rather than leaking into custom sync transports.
public enum SyncFieldValue: Sendable, Equatable {
  case null
  case integer(Int64)
  case double(Double)
  case string(String)
  case data(Data)
  case date(Date)
}

public struct RemoteRecord: Sendable, Equatable {
  public var recordName: String
  public var recordType: String
  public var fields: [String: SyncFieldValue]
  /// Opaque transport metadata, such as archived CloudKit system fields.
  public var transportMetadata: Data?

  public init(
    recordName: String,
    recordType: String,
    fields: [String: SyncFieldValue],
    transportMetadata: Data? = nil
  ) {
    self.recordName = recordName
    self.recordType = recordType
    self.fields = fields
    self.transportMetadata = transportMetadata
  }
}

/// Transport-agnostic remote mutation used by ``SyncAdapter/applyRemoteChanges(_:)``.
public enum RemoteChange: Sendable, Equatable {
  case upsert(RemoteRecord)
  case delete(recordName: String)
}

/// Default CloudKit-backed ``SyncAdapter``.
public final actor CloudKitSyncAdapter: SyncAdapter {
  nonisolated public let engine: TursoCKSyncEngine

  private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
  private var currentStatus: SyncStatus = .idle

  public init(engine: TursoCKSyncEngine) async {
    self.engine = engine
    await engine.setStatusSink { [weak self] status in
      Task { await self?.publish(status) }
    }
  }

  public init(
    connection: TursoConnection,
    configuration: TursoCKSyncConfiguration,
    container: CKContainer? = nil
  ) async throws {
    await self.init(
      engine: try await TursoCKSyncEngine(
        connection: connection,
        configuration: configuration,
        container: container
      )
    )
  }

  public func start() async throws {
    try await start(automaticallySync: engine.configuration.enablesCloudKit)
  }

  /// Starts with an explicit CKSyncEngine scheduling policy.
  public func start(automaticallySync: Bool) async throws {
    publish(.syncing)
    do {
      try await engine.start(automaticallySync: automaticallySync)
      try await engine.detectAccountIdentityChangeIfNeeded()
      publish(.idle)
    } catch {
      publish(.failed(error.localizedDescription))
      throw error
    }
  }

  public func stop() async {
    await engine.stop()
    publish(.idle)
  }

  public func syncStatus() async -> AsyncStream<SyncStatus> {
    AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
      let id = UUID()
      self.statusContinuations[id] = continuation
      continuation.yield(self.currentStatus)
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeContinuation(id) }
      }
    }
  }

  @discardableResult
  public func drainLocalChanges() async throws -> Int {
    publish(.syncing)
    do {
      let count = try await engine.drainCDC(limit: engine.configuration.drainCDCLimit)
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
          try await engine.applyRemoteRecord(makeCloudKitRecord(from: record))
        case .delete(let recordName):
          try await engine.applyRemoteDeletion(
            recordID: CKRecord.ID(recordName: recordName, zoneID: engine.zoneID)
          )
        }
      }
      publish(.idle)
    } catch {
      publish(.failed(error.localizedDescription))
      throw error
    }
  }

  public func fetchChanges() async throws {
    guard engine.configuration.enablesCloudKit else { return }
    publish(.syncing)
    do {
      try await engine.requireEngine().fetchChanges()
      publish(.idle)
    } catch {
      publish(.failed(error.localizedDescription))
      throw error
    }
  }

  public func sendChanges() async throws {
    _ = try await drainLocalChanges()
    guard engine.configuration.enablesCloudKit else { return }
    publish(.syncing)
    do {
      try await engine.requireEngine().sendChanges()
      publish(.idle)
    } catch {
      publish(.failed(error.localizedDescription))
      throw error
    }
  }

  public func syncChanges() async throws {
    try await fetchChanges()
    try await sendChanges()
  }

  private func makeCloudKitRecord(from record: RemoteRecord) async throws -> CKRecord {
    let recordID = CKRecord.ID(recordName: record.recordName, zoneID: engine.zoneID)
    let cloudRecord: CKRecord
    if let metadata = record.transportMetadata {
      guard let decoded = RecordMapper.decodeSystemFields(metadata) else {
        throw TursoCKSyncError.invalidTransportMetadata("cannot decode CloudKit system fields")
      }
      guard decoded.recordID == recordID else {
        throw TursoCKSyncError.invalidTransportMetadata(
          "record identifier does not match '\(record.recordName)'"
        )
      }
      guard decoded.recordType == record.recordType else {
        throw TursoCKSyncError.invalidTransportMetadata(
          "record type does not match '\(record.recordType)'"
        )
      }
      cloudRecord = decoded
    } else {
      cloudRecord = CKRecord(recordType: record.recordType, recordID: recordID)
    }
    for (key, value) in record.fields {
      switch value {
      case .null: cloudRecord[key] = nil
      case .integer(let value): cloudRecord[key] = NSNumber(value: value)
      case .double(let value): cloudRecord[key] = NSNumber(value: value)
      case .string(let value): cloudRecord[key] = value as NSString
      case .data(let value): cloudRecord[key] = value as NSData
      case .date(let value): cloudRecord[key] = value as NSDate
      }
    }
    return cloudRecord
  }

  private func publish(_ status: SyncStatus) {
    currentStatus = status
    for cont in statusContinuations.values {
      cont.yield(status)
    }
  }

  private func removeContinuation(_ id: UUID) {
    statusContinuations[id] = nil
  }
}
