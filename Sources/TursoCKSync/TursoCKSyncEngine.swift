import CloudKit
import Foundation
import os.log
import TursoKit

private let logger = Logger(subsystem: "TursoCKSync", category: "engine")

/// Bridges Turso CDC ↔ `CKSyncEngine` for the private CloudKit database.
///
/// Typical setup:
/// ```swift
/// let db = TursoDatabase(url: url)
/// let conn = try db.connect(enableCDC: true)
/// let engine = try TursoCKSyncEngine(
///   connection: conn,
///   configuration: .init(syncedTables: [
///     SyncedTable(name: "notes", columns: ["title", "body", "updatedAt"])
///   ])
/// )
/// try engine.start()
/// // after local writes:
/// try engine.drainCDC()
/// ```
public final class TursoCKSyncEngine: @unchecked Sendable {
  public let connection: TursoConnection
  public let configuration: TursoCKSyncConfiguration
  public let metadata: SyncMetadataStore

  private var container: CKContainer?
  private var syncEngine: CKSyncEngine?
  /// In-process pending queue used when `enablesCloudKit == false`.
  private var localPendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
  private let lock = NSLock()
  private var zoneBootstrapped = false

  public var zoneID: CKRecordZone.ID {
    CKRecordZone.ID(zoneName: configuration.zoneName, ownerName: CKCurrentUserDefaultName)
  }

  /// Pending record changes waiting to sync (CloudKit engine state or local queue).
  public var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
    lock.lock()
    defer { lock.unlock() }
    if let syncEngine {
      return syncEngine.state.pendingRecordZoneChanges
    }
    return localPendingRecordZoneChanges
  }

  public init(
    connection: TursoConnection,
    configuration: TursoCKSyncConfiguration,
    container: CKContainer? = nil
  ) throws {
    self.connection = connection
    self.configuration = configuration
    self.metadata = SyncMetadataStore(connection: connection)
    if configuration.enablesCloudKit {
      if let container {
        self.container = container
      } else if let id = configuration.containerIdentifier {
        self.container = CKContainer(identifier: id)
      } else {
        // Prefer an explicit identifier — `CKContainer.default()` traps when the
        // host process has no CloudKit container entitlement (e.g. `swift test`).
        self.container = CKContainer(identifier: "iCloud.com.turso.cloudkit.dev")
      }
    }
    try metadata.migrate()
    try connection.enableCaptureDataChanges(mode: .full)
  }

  /// Creates `CKSyncEngine` with persisted `stateSerialization` and ensures the custom zone is pending.
  public func start(automaticallySync: Bool = true) throws {
    guard configuration.enablesCloudKit else {
      logger.log("CloudKit disabled — using in-process pending queue")
      return
    }
    lock.lock()
    defer { lock.unlock() }
    guard syncEngine == nil else { return }
    guard let container else {
      throw TursoError(code: -1, message: "Missing CKContainer")
    }

    let state = try metadata.loadStateSerialization()
    var config = CKSyncEngine.Configuration(
      database: container.privateCloudDatabase,
      stateSerialization: state,
      delegate: self
    )
    config.automaticallySync = automaticallySync
    let engine = CKSyncEngine(config)
    self.syncEngine = engine

    if state == nil {
      engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
      zoneBootstrapped = true
    }
    logger.log("CKSyncEngine started (hasState=\(state != nil, privacy: .public))")
  }

  public func requireEngine() throws -> CKSyncEngine {
    lock.lock()
    defer { lock.unlock() }
    guard let syncEngine else {
      throw TursoError(code: -1, message: "Call start() before using the sync engine")
    }
    return syncEngine
  }

  // MARK: - Outbound (CDC → pending)

  /// Drains `turso_cdc` into `pendingRecordZoneChanges`. Call after local commits (or on a timer).
  @discardableResult
  public func drainCDC(limit: Int = 500) throws -> Int {
    if connection.isSynchronizing { return 0 }

    let cursor = try metadata.loadCDCCursor()
    let changes = try connection.cdcChanges(after: cursor, limit: limit)
    guard !changes.isEmpty else { return 0 }

    var pending: [CKSyncEngine.PendingRecordZoneChange] = []
    var lastID = cursor

    for change in changes {
      lastID = change.changeID
      guard configuration.syncedTableNames.contains(change.tableName),
        let table = configuration.table(named: change.tableName)
      else { continue }

      guard let rowPK = try resolveRowPK(table: table, change: change), !rowPK.isEmpty
      else { continue }

      let recordID = CKRecord.ID(
        recordName: table.recordName(forRowPK: rowPK),
        zoneID: zoneID
      )

      if change.isDelete {
        pending.append(.deleteRecord(recordID))
      } else {
        pending.append(.saveRecord(recordID))
      }
    }

    if !pending.isEmpty {
      enqueuePending(pending)
    }
    try metadata.saveCDCCursor(lastID)
    logger.debug("Drained \(pending.count, privacy: .public) pending changes (cursor=\(lastID, privacy: .public))")
    return pending.count
  }

  private func enqueuePending(_ pending: [CKSyncEngine.PendingRecordZoneChange]) {
    lock.lock()
    defer { lock.unlock() }
    if let syncEngine {
      syncEngine.state.add(pendingRecordZoneChanges: pending)
    } else {
      localPendingRecordZoneChanges.append(contentsOf: pending)
    }
  }

  /// Convenience: local write that then drains CDC.
  @discardableResult
  public func performLocalWrite(_ body: () throws -> Void) throws -> Int {
    try connection.write(body)
    return try drainCDC()
  }

  // MARK: - Testing helpers (no network)

  /// Builds a `CKRecord` for the current local row (used by tests / recordProvider).
  public func makeRecord(for recordID: CKRecord.ID) throws -> CKRecord? {
    guard let parsed = RecordIdentity.parse(recordID.recordName),
      let table = configuration.table(named: parsed.table),
      let row = try RowSQL.fetchRow(connection: connection, table: table, rowPK: parsed.rowPK)
    else { return nil }

    let systemFields = try metadata.systemFields(table: table.name, rowPK: parsed.rowPK)
    return try RecordMapper.makeRecord(
      table: table,
      rowPK: parsed.rowPK,
      row: row,
      zoneID: zoneID,
      systemFields: systemFields
    )
  }

  /// Applies a remote record as if delivered by `fetchedRecordZoneChanges`.
  public func applyRemoteRecord(_ record: CKRecord) throws {
    try applyModification(record)
  }

  public func applyRemoteDeletion(recordID: CKRecord.ID) throws {
    try applyDeletion(recordID)
  }

  // MARK: - Inbound

  private func applyModification(_ record: CKRecord) throws {
    guard let table = configuration.table(forRecordType: record.recordType)
      ?? configuration.table(named: RecordIdentity.parse(record.recordID.recordName)?.table ?? "")
    else {
      logger.info("Ignoring unknown record type \(record.recordType, privacy: .public)")
      return
    }

    let rowPK =
      RecordIdentity.rowPK(table: table.name, recordName: record.recordID.recordName)
      ?? (record[table.primaryKeyColumn] as? String)
    guard let rowPK else {
      throw TursoError(code: -1, message: "Cannot resolve PK for \(record.recordID.recordName)")
    }

    let row = RecordMapper.rowDictionary(from: record, table: table)
    let systemFields = RecordMapper.encodeSystemFields(record)
    let cursorBefore = try metadata.loadCDCCursor()

    connection.isSynchronizing = true
    defer { connection.isSynchronizing = false }

    try connection.write {
      try RowSQL.upsert(connection: connection, table: table, row: row)
      try metadata.upsertRecordMeta(
        table: table.name,
        rowPK: rowPK,
        recordName: record.recordID.recordName,
        zoneName: record.recordID.zoneID.zoneName,
        systemFields: systemFields
      )
      // Skip CDC rows produced by this inbound apply.
      try advanceCDCCursorPastEcho(from: cursorBefore)
    }
  }

  private func applyDeletion(_ recordID: CKRecord.ID) throws {
    let resolved: (table: String, rowPK: String)?
    if let parsed = RecordIdentity.parse(recordID.recordName) {
      resolved = parsed
    } else {
      resolved = try metadata.resolveRow(recordName: recordID.recordName)
    }

    guard let resolved, let table = configuration.table(named: resolved.table) else {
      try? metadata.deleteRecordMeta(recordName: recordID.recordName)
      return
    }

    let cursorBefore = try metadata.loadCDCCursor()
    connection.isSynchronizing = true
    defer { connection.isSynchronizing = false }

    try connection.write {
      try RowSQL.delete(connection: connection, table: table, rowPK: resolved.rowPK)
      try metadata.deleteRecordMeta(table: table.name, rowPK: resolved.rowPK)
      try advanceCDCCursorPastEcho(from: cursorBefore)
    }
  }

  private func advanceCDCCursorPastEcho(from cursorBefore: Int64) throws {
    let changes = try connection.cdcChanges(after: cursorBefore, limit: 10_000)
    if let last = changes.last {
      try metadata.saveCDCCursor(last.changeID)
    }
  }

  // MARK: - Conflicts / account

  private func handleServerRecordChanged(
    failedRecord: CKRecord,
    serverRecord: CKRecord,
    engine: CKSyncEngine
  ) throws {
    switch configuration.conflictPolicy {
    case .serverWins:
      try applyModification(serverRecord)
    case .clientWins:
      try applyModification(serverRecord)  // keep system fields
      engine.state.add(pendingRecordZoneChanges: [.saveRecord(failedRecord.recordID)])
    case .lastWriterWins(let field):
      let local = try makeRecord(for: failedRecord.recordID)
      let localStamp = comparableStamp(local?[field])
      let serverStamp = comparableStamp(serverRecord[field])
      if let localStamp, let serverStamp, localStamp > serverStamp {
        try metadata.upsertRecordMeta(
          table: RecordIdentity.parse(failedRecord.recordID.recordName)?.table ?? "",
          rowPK: RecordIdentity.parse(failedRecord.recordID.recordName)?.rowPK ?? "",
          recordName: failedRecord.recordID.recordName,
          zoneName: zoneID.zoneName,
          systemFields: RecordMapper.encodeSystemFields(serverRecord)
        )
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(failedRecord.recordID)])
      } else {
        try applyModification(serverRecord)
      }
    }
  }

  private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) throws {
    let shouldWipe: Bool
    let shouldReupload: Bool
    switch event.changeType {
    case .signIn:
      shouldWipe = false
      shouldReupload = true
    case .switchAccounts, .signOut:
      shouldWipe = true
      shouldReupload = false
    @unknown default:
      shouldWipe = false
      shouldReupload = false
    }

    if shouldWipe {
      try wipeAndRebootstrap()
    }

    if shouldReupload {
      if configuration.enablesCloudKit, let engine = try? requireEngine() {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
      }
      try enqueueAllLocalRows()
    }
  }

  public func wipeAndRebootstrap() throws {
    connection.isSynchronizing = true
    defer { connection.isSynchronizing = false }
    try connection.write {
      try RowSQL.deleteAllSyncedData(connection: connection, tables: configuration.syncedTables)
      try metadata.wipeAll()
    }
    lock.lock()
    syncEngine = nil
    localPendingRecordZoneChanges = []
    lock.unlock()
    try start()
  }

  private func enqueueAllLocalRows() throws {
    var pending: [CKSyncEngine.PendingRecordZoneChange] = []
    for table in configuration.syncedTables {
      let rows = try connection.query(
        "SELECT \(RowSQL.quoteIdent(table.primaryKeyColumn)) AS pk FROM \(RowSQL.quoteIdent(table.name))"
      )
      for row in rows {
        guard let pk = row["pk"]?.stringValue ?? row["pk"]?.int64Value.map(String.init) else {
          continue
        }
        let recordID = CKRecord.ID(recordName: table.recordName(forRowPK: pk), zoneID: zoneID)
        pending.append(.saveRecord(recordID))
      }
    }
    if !pending.isEmpty {
      enqueuePending(pending)
    }
  }

  private func rowPKString(from value: TursoValue) -> String {
    switch value {
    case .text(let s): return s
    case .integer(let i): return String(i)
    case .double(let d): return String(Int64(d))
    case .blob(let data): return String(data: data, encoding: .utf8) ?? ""
    case .null: return ""
    }
  }

  /// Turso CDC `id` is often the integer rowid even when the table PK is TEXT.
  /// Resolve the configured primary-key column value for CloudKit record names.
  private func resolveRowPK(table: SyncedTable, change: CDCChange) throws -> String? {
    if case .text(let text) = change.rowID, !text.isEmpty {
      return text
    }

    if !change.isDelete {
      if let rowid = change.rowID.int64Value {
        let row = try connection.queryOne(
          """
          SELECT \(RowSQL.quoteIdent(table.primaryKeyColumn)) AS pk
          FROM \(RowSQL.quoteIdent(table.name))
          WHERE rowid = ?
          LIMIT 1
          """,
          [.integer(rowid)]
        )
        if let value = row?["pk"] {
          let pk = rowPKString(from: value)
          if !pk.isEmpty { return pk }
        }
      }
      if let payload = try decodeCDCPayload(table: table, blob: change.after),
        let value = payload[table.primaryKeyColumn]
      {
        let pk = rowPKString(from: value)
        if !pk.isEmpty { return pk }
      }
    } else if let payload = try decodeCDCPayload(table: table, blob: change.before),
      let value = payload[table.primaryKeyColumn]
    {
      let pk = rowPKString(from: value)
      if !pk.isEmpty { return pk }
    }

    let fallback = rowPKString(from: change.rowID)
    return fallback.isEmpty ? nil : fallback
  }

  private func decodeCDCPayload(table: SyncedTable, blob: Data?) throws -> [String: TursoValue]? {
    guard let blob, !blob.isEmpty else { return nil }
    let rows = try connection.query(
      """
      SELECT bin_record_json_object(
        table_columns_json_array(?),
        ?
      ) AS payload
      """,
      [.text(table.name), .blob(blob)]
    )
    guard let json = rows.first?["payload"]?.stringValue,
      let data = json.data(using: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    var result: [String: TursoValue] = [:]
    for (key, value) in object {
      switch value {
      case let s as String: result[key] = .text(s)
      case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
          result[key] = .integer(n.boolValue ? 1 : 0)
        } else if n.doubleValue.rounded() == n.doubleValue {
          result[key] = .integer(n.int64Value)
        } else {
          result[key] = .double(n.doubleValue)
        }
      case is NSNull: result[key] = .null
      default: result[key] = .text(String(describing: value))
      }
    }
    return result
  }

  private func comparableStamp(_ value: CKRecordValue?) -> Double? {
    switch value {
    case let number as NSNumber:
      return number.doubleValue
    case let string as NSString:
      if let date = try? Date(string as String, strategy: .iso8601) {
        return date.timeIntervalSince1970
      }
      return Double(string as String)
    case let date as NSDate:
      return (date as Date).timeIntervalSince1970
    default:
      return nil
    }
  }
}

// MARK: - CKSyncEngineDelegate

extension TursoCKSyncEngine: CKSyncEngineDelegate {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    do {
      switch event {
      case .stateUpdate(let update):
        try metadata.saveStateSerialization(update.stateSerialization)

      case .accountChange(let change):
        try handleAccountChange(change)

      case .fetchedDatabaseChanges(let changes):
        for deletion in changes.deletions where deletion.zoneID == zoneID {
          try wipeAndRebootstrap()
        }

      case .fetchedRecordZoneChanges(let changes):
        for modification in changes.modifications {
          try applyModification(modification.record)
        }
        for deletion in changes.deletions {
          try applyDeletion(deletion.recordID)
        }

      case .sentRecordZoneChanges(let sent):
        try handleSentRecordZoneChanges(sent, syncEngine: syncEngine)

      case .sentDatabaseChanges:
        zoneBootstrapped = true

      case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
        .didFetchChanges, .willSendChanges, .didSendChanges:
        break

      @unknown default:
        logger.info("Unknown CKSyncEngine event")
      }
    } catch {
      logger.error("handleEvent failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let scope = context.options.scope
    var changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
    if changes.isEmpty { return nil }

    if changes.count > configuration.maxBatchSize {
      changes = Array(changes.prefix(configuration.maxBatchSize))
    }

    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] recordID in
      guard let self else { return nil }
      do {
        if let record = try self.makeRecord(for: recordID) {
          return record
        }
        // Local row gone — drop the save.
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
      } catch {
        logger.error("recordProvider failed: \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }
  }

  private func handleSentRecordZoneChanges(
    _ event: CKSyncEngine.Event.SentRecordZoneChanges,
    syncEngine: CKSyncEngine
  ) throws {
    for saved in event.savedRecords {
      guard let parsed = RecordIdentity.parse(saved.recordID.recordName) else { continue }
      try metadata.upsertRecordMeta(
        table: parsed.table,
        rowPK: parsed.rowPK,
        recordName: saved.recordID.recordName,
        zoneName: saved.recordID.zoneID.zoneName,
        systemFields: RecordMapper.encodeSystemFields(saved)
      )
    }

    var retryRecords: [CKSyncEngine.PendingRecordZoneChange] = []
    var retryZones: [CKSyncEngine.PendingDatabaseChange] = []

    for failure in event.failedRecordSaves {
      switch failure.error.code {
      case .serverRecordChanged:
        if let server = failure.error.serverRecord {
          try handleServerRecordChanged(
            failedRecord: failure.record,
            serverRecord: server,
            engine: syncEngine
          )
        }
      case .zoneNotFound:
        retryZones.append(.saveZone(CKRecordZone(zoneID: failure.record.recordID.zoneID)))
        retryRecords.append(.saveRecord(failure.record.recordID))
      case .unknownItem:
        if let parsed = RecordIdentity.parse(failure.record.recordID.recordName) {
          try metadata.upsertRecordMeta(
            table: parsed.table,
            rowPK: parsed.rowPK,
            recordName: failure.record.recordID.recordName,
            zoneName: zoneID.zoneName,
            systemFields: nil
          )
        }
        retryRecords.append(.saveRecord(failure.record.recordID))
      case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
        .operationCancelled:
        break
      default:
        logger.error("Unhandled save failure: \(failure.error.localizedDescription, privacy: .public)")
      }
    }

    if !retryZones.isEmpty {
      syncEngine.state.add(pendingDatabaseChanges: retryZones)
    }
    if !retryRecords.isEmpty {
      syncEngine.state.add(pendingRecordZoneChanges: retryRecords)
    }
  }
}
