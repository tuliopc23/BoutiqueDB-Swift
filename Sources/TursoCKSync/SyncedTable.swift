import CloudKit
import Foundation
import TursoKit

/// Describes a user table that participates in CloudKit sync.
public struct SyncedTable: Sendable, Hashable {
  public var name: String
  /// Column used as the stable primary key (UUID string preferred).
  public var primaryKeyColumn: String
  /// Columns synced to CloudKit (excluding the PK, which becomes the record name suffix).
  public var columns: [String]
  /// CloudKit record type. Defaults to the table name.
  public var recordType: CKRecord.RecordType

  public init(
    name: String,
    primaryKeyColumn: String = "id",
    columns: [String],
    recordType: CKRecord.RecordType? = nil
  ) {
    self.name = name
    self.primaryKeyColumn = primaryKeyColumn
    self.columns = columns
    self.recordType = recordType ?? CKRecord.RecordType(name)
  }

  public func recordName(forRowPK rowPK: String) -> String {
    RecordIdentity.recordName(table: name, rowPK: rowPK)
  }

  public func parseRecordName(_ recordName: String) -> String? {
    RecordIdentity.rowPK(table: name, recordName: recordName)
  }
}

enum RecordIdentity {
  static func recordName(table: String, rowPK: String) -> String {
    // CloudKit: no leading underscore, ≤ 255 chars.
    let raw = "\(table):\(rowPK)"
    precondition(!raw.hasPrefix("_"))
    precondition(raw.count <= 255)
    return raw
  }

  static func parse(_ recordName: String) -> (table: String, rowPK: String)? {
    guard let idx = recordName.firstIndex(of: ":") else { return nil }
    let table = String(recordName[..<idx])
    let rowPK = String(recordName[recordName.index(after: idx)...])
    guard !table.isEmpty, !rowPK.isEmpty else { return nil }
    return (table, rowPK)
  }

  static func rowPK(table: String, recordName: String) -> String? {
    guard let parsed = parse(recordName), parsed.table == table else { return nil }
    return parsed.rowPK
  }
}

public enum ConflictPolicy: Sendable {
  /// Prefer the server record (CloudKit wins).
  case serverWins
  /// Prefer the client record (re-pend local save).
  case clientWins
  /// Last-writer-wins using a comparable field on the record (e.g. `updatedAt`).
  case lastWriterWins(field: String)
}

public struct TursoCKSyncConfiguration: Sendable {
  public var containerIdentifier: String?
  public var zoneName: String
  public var syncedTables: [SyncedTable]
  public var conflictPolicy: ConflictPolicy
  /// Soft cap for records per `RecordZoneChangeBatch` (CloudKit max 250).
  public var maxBatchSize: Int
  /// Max CDC rows read per ``TursoCKSyncEngine/drainCDC(limit:)`` call (default 500).
  public var drainCDCLimit: Int
  /// When `false`, CDC drain keeps pending changes in-process (for unit tests /
  /// hosts without CloudKit entitlements). Set `true` in production apps.
  public var enablesCloudKit: Bool

  public init(
    containerIdentifier: String? = nil,
    zoneName: String = "app.default",
    syncedTables: [SyncedTable],
    conflictPolicy: ConflictPolicy = .serverWins,
    maxBatchSize: Int = 250,
    drainCDCLimit: Int = 500,
    enablesCloudKit: Bool = true
  ) {
    self.containerIdentifier = containerIdentifier
    self.zoneName = zoneName
    self.syncedTables = syncedTables
    self.conflictPolicy = conflictPolicy
    self.maxBatchSize = min(max(1, maxBatchSize), 250)
    self.drainCDCLimit = max(1, drainCDCLimit)
    self.enablesCloudKit = enablesCloudKit
  }

  public func table(named name: String) -> SyncedTable? {
    syncedTables.first { $0.name == name }
  }

  public func table(forRecordType type: CKRecord.RecordType) -> SyncedTable? {
    syncedTables.first { $0.recordType == type }
  }

  public var syncedTableNames: Set<String> {
    Set(syncedTables.map(\.name))
  }
}
