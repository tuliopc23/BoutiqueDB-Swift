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

  public func recordName(forRowPK rowPK: String) throws -> String {
    try RecordIdentity.recordName(table: name, rowPK: rowPK)
  }

  public func parseRecordName(_ recordName: String) -> String? {
    RecordIdentity.rowPK(table: name, recordName: recordName)
  }
}

enum RecordIdentity {
  static func recordName(table: String, rowPK: String) throws -> String {
    let raw = "\(table):\(rowPK)"
    guard !rowPK.isEmpty else {
      throw TursoCKSyncError.invalidRecordName("primary key is empty")
    }
    guard !raw.hasPrefix("_") else {
      throw TursoCKSyncError.invalidRecordName("record names cannot start with '_'")
    }
    guard raw.utf8.count <= 255 else {
      throw TursoCKSyncError.invalidRecordName("record name exceeds 255 UTF-8 bytes")
    }
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

/// Configuration and durability failures detected before CloudKit state is advanced.
public enum TursoCKSyncError: Error, Sendable, Equatable, LocalizedError {
  case missingCloudKitContainer
  case invalidConfiguration(String)
  case invalidRecordName(String)
  case tableNotFound(String)
  case columnNotFound(table: String, column: String)
  case primaryKeyRequired(table: String, column: String)
  case compoundPrimaryKeyUnsupported(table: String)
  case autoIncrementPrimaryKeyUnsupported(table: String)
  case uniqueConstraintUnsupported(table: String, index: String)
  case unsupportedColumnType(table: String, column: String, type: String)
  case incompatibleSchemaMigration(table: String, reason: String)
  case unresolvedPrimaryKey(table: String, changeID: Int64)
  case assetReadFailed(field: String, message: String)
  case unsupportedRemoteValue(field: String, type: String)
  case invalidTransportMetadata(String)

  public var errorDescription: String? {
    switch self {
    case .missingCloudKitContainer:
      return "CloudKit sync requires an explicit container identifier or injected CKContainer"
    case .invalidConfiguration(let message), .invalidRecordName(let message):
      return message
    case .tableNotFound(let table):
      return "Synced table '\(table)' does not exist"
    case .columnNotFound(let table, let column):
      return "Synced column '\(table).\(column)' does not exist"
    case .primaryKeyRequired(let table, let column):
      return "Synced table '\(table)' requires '\(column)' to be its primary key"
    case .compoundPrimaryKeyUnsupported(let table):
      return "Synced table '\(table)' cannot use a compound primary key"
    case .autoIncrementPrimaryKeyUnsupported(let table):
      return "Synced table '\(table)' cannot use AUTOINCREMENT"
    case .uniqueConstraintUnsupported(let table, let index):
      return "Synced table '\(table)' has unsupported unique index '\(index)'"
    case .unsupportedColumnType(let table, let column, let type):
      return "Synced column '\(table).\(column)' has unsupported SQLite type '\(type)'"
    case .incompatibleSchemaMigration(let table, let reason):
      return "Synced table '\(table)' changed incompatibly: \(reason)"
    case .unresolvedPrimaryKey(let table, let changeID):
      return "Cannot resolve the primary key for '\(table)' CDC change \(changeID)"
    case .assetReadFailed(let field, let message):
      return "Cannot read CloudKit asset for field '\(field)': \(message)"
    case .unsupportedRemoteValue(let field, let type):
      return "Unsupported CloudKit value type '\(type)' for field '\(field)'"
    case .invalidTransportMetadata(let message):
      return "Invalid remote transport metadata: \(message)"
    }
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

  func validate(hasInjectedContainer: Bool) throws {
    if enablesCloudKit && containerIdentifier == nil && !hasInjectedContainer {
      throw TursoCKSyncError.missingCloudKitContainer
    }
    guard !zoneName.isEmpty else {
      throw TursoCKSyncError.invalidConfiguration("CloudKit zone name cannot be empty")
    }
    guard !syncedTables.isEmpty else {
      throw TursoCKSyncError.invalidConfiguration("At least one synced table is required")
    }

    let reservedFields: Set<String> = [
      "creationDate", "creatorUserRecordID", "etag", "lastModifiedUserRecordID",
      "modificationDate", "modifiedByDevice", "recordChangeTag", "recordID", "recordType",
    ]
    var tableNames = Set<String>()
    var recordTypes = Set<CKRecord.RecordType>()
    for table in syncedTables {
      guard !table.name.isEmpty, !table.name.hasPrefix("_") else {
        throw TursoCKSyncError.invalidConfiguration(
          "Synced table names cannot be empty or start with '_': '\(table.name)'"
        )
      }
      guard !table.primaryKeyColumn.isEmpty else {
        throw TursoCKSyncError.invalidConfiguration(
          "Synced table '\(table.name)' has an empty primary-key column"
        )
      }
      guard tableNames.insert(table.name).inserted else {
        throw TursoCKSyncError.invalidConfiguration("Duplicate synced table '\(table.name)'")
      }
      guard recordTypes.insert(table.recordType).inserted else {
        throw TursoCKSyncError.invalidConfiguration(
          "Duplicate CloudKit record type '\(table.recordType)'"
        )
      }
      var columns = Set<String>()
      for column in table.columns {
        guard !column.isEmpty, columns.insert(column).inserted else {
          throw TursoCKSyncError.invalidConfiguration(
            "Synced table '\(table.name)' contains an empty or duplicate column"
          )
        }
        guard column != table.primaryKeyColumn else {
          throw TursoCKSyncError.invalidConfiguration(
            "Synced columns for '\(table.name)' must exclude primary key '\(column)'"
          )
        }
      }
      for field in [table.primaryKeyColumn] + table.columns where reservedFields.contains(field) {
        throw TursoCKSyncError.invalidConfiguration(
          "Synced field '\(table.name).\(field)' is reserved by CloudKit"
        )
      }
    }
  }
}
