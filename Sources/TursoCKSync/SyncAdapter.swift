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
    try await start(automaticallySync: engine.configuration.enablesCloudKit)
  }

  /// Starts with an explicit CKSyncEngine scheduling policy.
  public func start(automaticallySync: Bool) async throws {
    publish(.syncing)
    do {
      try engine.start(automaticallySync: automaticallySync)
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
      let initialStatus = currentStatus
      statusLock.unlock()
      continuation.yield(initialStatus)
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.statusLock.lock()
        self.statusContinuations[id] = nil
        self.statusLock.unlock()
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
          try engine.applyRemoteRecord(makeCloudKitRecord(from: record))
        case .delete(let recordName):
          try engine.applyRemoteDeletion(
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

  private func makeCloudKitRecord(from record: RemoteRecord) throws -> CKRecord {
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
    statusLock.lock()
    currentStatus = status
    let conts = statusContinuations.values
    statusLock.unlock()
    for cont in conts {
      cont.yield(status)
    }
  }
}
