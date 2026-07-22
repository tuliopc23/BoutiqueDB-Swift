import CloudKit
import Foundation
import TursoKit
import os.log

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

  /// Optional sink for ``SyncStatus`` (wired by ``CloudKitSyncAdapter``).
  public var statusSink: (@Sendable (SyncStatus) -> Void)? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _statusSink
    }
    set {
      lock.lock()
      _statusSink = newValue
      lock.unlock()
    }
  }

  private var container: CKContainer?
  private var syncEngine: CKSyncEngine?
  /// In-process pending queue used when `enablesCloudKit == false`.
  private var localPendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
  private let lock = NSLock()
  private var _statusSink: (@Sendable (SyncStatus) -> Void)?
  private var zoneBootstrapped = false
  private var stopped = false

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
    try configuration.validate(hasInjectedContainer: container != nil)
    self.connection = connection
    self.configuration = configuration
    self.metadata = SyncMetadataStore(connection: connection)
    if configuration.enablesCloudKit {
      if let container {
        self.container = container
      } else if let id = configuration.containerIdentifier {
        self.container = CKContainer(identifier: id)
      }
    }
    try metadata.migrate()
    try validateDatabaseSchema()
    try metadata.validateAndSaveSchema(configuration.syncedTables)
    try connection.enableCaptureDataChanges(mode: .full)
  }

  /// Creates `CKSyncEngine` with persisted `stateSerialization` and ensures the custom zone is pending.
  public func start(automaticallySync: Bool = true) throws {
    stopped = false
    guard configuration.enablesCloudKit else {
      try restorePendingChanges()
      logger.log("CloudKit disabled — using in-process pending queue")
      publishStatus(.idle)
      return
    }
    lock.lock()
    guard syncEngine == nil else {
      lock.unlock()
      return
    }
    guard let container else {
      lock.unlock()
      throw TursoError(code: -1, message: "Missing CKContainer")
    }

    let state: CKSyncEngine.State.Serialization?
    do {
      state = try metadata.loadStateSerialization()
    } catch {
      lock.unlock()
      throw error
    }
    var config = CKSyncEngine.Configuration(
      database: container.privateCloudDatabase,
      stateSerialization: state,
      delegate: self
    )
    config.automaticallySync = automaticallySync
    let engine = CKSyncEngine(config)
    self.syncEngine = engine
    lock.unlock()

    if state == nil {
      engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
      zoneBootstrapped = true
    }
    try restorePendingChanges()
    logger.log("CKSyncEngine started (hasState=\(state != nil, privacy: .public))")
    publishStatus(.idle)
  }

  /// Tears down the CloudKit engine (local pending queue is retained for tests).
  public func stop() {
    lock.lock()
    syncEngine = nil
    stopped = true
    lock.unlock()
    publishStatus(.idle)
  }

  /// Persist / compare account identity hash for crash-safe rebootstrap (BD-007).
  ///
  /// Call with a stable hash of the signed-in Apple ID (e.g. `userRecordID.recordName`).
  public func noteAccountIdentity(_ accountHash: String?) throws {
    let previous = try metadata.loadAccountHash()
    if let previous, let accountHash, previous != accountHash {
      publishStatus(.accountChanged)
      try wipeAndRebootstrap(preserveLocalUserData: true)
    }
    try metadata.saveAccountHash(accountHash)
  }

  /// Optional synchronous account status for tests / custom UI (inject before start).
  public var injectedAccountStatus: CKAccountStatus?

  /// Account probe when CloudKit is enabled.
  ///
  /// Uses ``injectedAccountStatus`` when set; otherwise awaits
  /// `CKContainer.accountStatus` and preserves any CloudKit failure for the caller.
  /// Live apps should also call ``noteAccountIdentity`` / ``applyAccountStatus`` from
  /// account-change notifications.
  public func detectAccountIdentityChangeIfNeeded() async throws {
    guard configuration.enablesCloudKit else { return }
    _ = try metadata.loadAccountHash()
    if let injectedAccountStatus {
      try applyAccountStatus(injectedAccountStatus)
      return
    }
    guard let container else { return }
    try applyAccountStatus(await container.accountStatus())
  }

  /// Applies a known ``CKAccountStatus`` (tests and custom UI flows).
  public func applyAccountStatus(_ status: CKAccountStatus) throws {
    switch status {
    case .available:
      break
    case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
      publishStatus(.needsAuthentication)
    @unknown default:
      publishStatus(.needsAuthentication)
    }
    _ = try metadata.loadAccountHash()
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
  ///
  /// - Parameter limit: Max CDC rows per call (defaults to ``TursoCKSyncConfiguration/drainCDCLimit``, 500).
  ///   CloudKit send path further batches to ``TursoCKSyncConfiguration/maxBatchSize`` (≤ 250).
  @discardableResult
  public func drainCDC(limit: Int? = nil) throws -> Int {
    if connection.isApplyingRemoteChanges { return 0 }
    if stopped { return 0 }

    let effectiveLimit = limit ?? configuration.drainCDCLimit
    let cursor = try metadata.loadCDCCursor()
    let changes = try connection.cdcChanges(after: cursor, limit: effectiveLimit)
    guard !changes.isEmpty else { return 0 }

    var durable: [DurablePendingChange] = []
    var lastID = cursor

    for change in changes {
      lastID = change.changeID
      guard configuration.syncedTableNames.contains(change.tableName),
        let table = configuration.table(named: change.tableName)
      else { continue }

      durable.append(try durablePendingChange(for: change, table: table))
    }

    durable = coalescing(durable)
    try metadata.stagePendingChanges(durable, through: lastID)
    enqueueDurableChanges(durable)
    logger.debug(
      "Drained \(durable.count, privacy: .public) pending changes (cursor=\(lastID, privacy: .public))"
    )
    return durable.count
  }

  private func enqueuePending(_ pending: [CKSyncEngine.PendingRecordZoneChange]) {
    lock.lock()
    defer { lock.unlock() }
    for change in pending {
      let recordID: CKRecord.ID
      switch change {
      case .saveRecord(let id), .deleteRecord(let id): recordID = id
      @unknown default: continue
      }
      let alternatives: [CKSyncEngine.PendingRecordZoneChange] = [
        .saveRecord(recordID), .deleteRecord(recordID),
      ]
      if let syncEngine {
        syncEngine.state.remove(pendingRecordZoneChanges: alternatives)
        syncEngine.state.add(pendingRecordZoneChanges: [change])
      } else {
        localPendingRecordZoneChanges.removeAll { existing in
          switch existing {
          case .saveRecord(let id), .deleteRecord(let id): return id == recordID
          @unknown default: return false
          }
        }
        localPendingRecordZoneChanges.append(change)
      }
    }
  }

  private func durablePendingChange(
    for change: CDCChange,
    table: SyncedTable
  ) throws -> DurablePendingChange {
    guard let rowPK = try resolveRowPK(table: table, change: change), !rowPK.isEmpty else {
      throw TursoCKSyncError.unresolvedPrimaryKey(table: table.name, changeID: change.changeID)
    }
    return DurablePendingChange(
      recordName: try table.recordName(forRowPK: rowPK),
      tableName: table.name,
      rowPK: rowPK,
      zoneName: zoneID.zoneName,
      operation: change.isDelete ? .delete : .save,
      changeID: change.changeID
    )
  }

  private func coalescing(_ changes: [DurablePendingChange]) -> [DurablePendingChange] {
    var latest: [String: DurablePendingChange] = [:]
    for change in changes {
      latest[change.recordName] = change
    }
    return latest.values.sorted {
      ($0.changeID, $0.recordName) < ($1.changeID, $1.recordName)
    }
  }

  private func enqueueDurableChanges(_ changes: [DurablePendingChange]) {
    enqueuePending(
      changes.map { change in
        let recordID = CKRecord.ID(recordName: change.recordName, zoneID: zoneID)
        switch change.operation {
        case .save: return .saveRecord(recordID)
        case .delete: return .deleteRecord(recordID)
        }
      }
    )
  }

  private func restorePendingChanges() throws {
    enqueueDurableChanges(try metadata.loadPendingChanges())
  }

  private func preserveClientRecord(serverRecord: CKRecord) throws {
    guard let parsed = RecordIdentity.parse(serverRecord.recordID.recordName),
      let table = configuration.table(named: parsed.table),
      try makeRecord(for: serverRecord.recordID) != nil
    else {
      throw TursoCKSyncError.unresolvedPrimaryKey(
        table: RecordIdentity.parse(serverRecord.recordID.recordName)?.table ?? "unknown",
        changeID: try metadata.loadCDCCursor()
      )
    }
    try metadata.upsertRecordMeta(
      table: table.name,
      rowPK: parsed.rowPK,
      recordName: serverRecord.recordID.recordName,
      zoneName: serverRecord.recordID.zoneID.zoneName,
      systemFields: RecordMapper.encodeSystemFields(serverRecord)
    )
    let cursor = try metadata.loadCDCCursor()
    let durable = DurablePendingChange(
      recordName: serverRecord.recordID.recordName,
      tableName: table.name,
      rowPK: parsed.rowPK,
      zoneName: serverRecord.recordID.zoneID.zoneName,
      operation: .save,
      changeID: cursor
    )
    try metadata.stagePendingChanges([durable], through: cursor)
    enqueueDurableChanges([durable])
  }

  private func validateDatabaseSchema() throws {
    for table in configuration.syncedTables {
      let columns = try connection.query("PRAGMA table_info(\(RowSQL.quoteIdent(table.name)))")
      guard !columns.isEmpty else {
        throw TursoCKSyncError.tableNotFound(table.name)
      }
      let primaryKeys = columns.filter { ($0["pk"]?.int64Value ?? 0) > 0 }
      guard primaryKeys.count <= 1 else {
        throw TursoCKSyncError.compoundPrimaryKeyUnsupported(table: table.name)
      }
      guard let primaryKey = primaryKeys.first,
        primaryKey["name"]?.stringValue == table.primaryKeyColumn
      else {
        throw TursoCKSyncError.primaryKeyRequired(
          table: table.name,
          column: table.primaryKeyColumn
        )
      }
      let availableColumns = Set(columns.compactMap { $0["name"]?.stringValue })
      for column in table.columns where !availableColumns.contains(column) {
        throw TursoCKSyncError.columnNotFound(table: table.name, column: column)
      }

      let declaredType = primaryKey["type"]?.stringValue?.uppercased() ?? ""
      let supportsStableIdentity =
        declaredType.contains("INT")
        || declaredType.contains("CHAR")
        || declaredType.contains("CLOB")
        || declaredType.contains("TEXT")
      guard supportsStableIdentity else {
        throw TursoCKSyncError.unsupportedColumnType(
          table: table.name,
          column: table.primaryKeyColumn,
          type: declaredType
        )
      }

      let createSQL =
        try connection.queryOne(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
          [.text(table.name)]
        )?["sql"]?.stringValue?.uppercased() ?? ""
      if createSQL.contains("AUTOINCREMENT") {
        throw TursoCKSyncError.autoIncrementPrimaryKeyUnsupported(table: table.name)
      }

      let indexes = try connection.query("PRAGMA index_list(\(RowSQL.quoteIdent(table.name)))")
      for index in indexes
      where index["unique"]?.int64Value == 1
        && index["origin"]?.stringValue != "pk"
      {
        throw TursoCKSyncError.uniqueConstraintUnsupported(
          table: table.name,
          index: index["name"]?.stringValue ?? "unknown"
        )
      }
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
    guard
      let table = configuration.table(forRecordType: record.recordType)
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

    let row = try RecordMapper.rowDictionary(from: record, table: table)
    let systemFields = RecordMapper.encodeSystemFields(record)
    let cursorBefore = try metadata.loadCDCCursor()

    let durable = try connection.withSynchronizingFlag {
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
        return try stageChangesPastEcho(
          from: cursorBefore,
          echoTable: table,
          echoRowPK: rowPK
        )
      }
    }
    enqueueDurableChanges(durable)
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
    let durable = try connection.withSynchronizingFlag {
      try connection.write {
        try RowSQL.delete(connection: connection, table: table, rowPK: resolved.rowPK)
        try metadata.deleteRecordMeta(table: table.name, rowPK: resolved.rowPK)
        return try stageChangesPastEcho(
          from: cursorBefore,
          echoTable: table,
          echoRowPK: resolved.rowPK
        )
      }
    }
    enqueueDurableChanges(durable)
  }

  private func stageChangesPastEcho(
    from cursorBefore: Int64,
    echoTable: SyncedTable,
    echoRowPK: String
  ) throws -> [DurablePendingChange] {
    let changes = try connection.cdcChanges(after: cursorBefore, limit: 10_000)
    guard let last = changes.last else { return [] }

    var echoChangeID: Int64?
    for change in changes where change.tableName == echoTable.name {
      if try resolveRowPK(table: echoTable, change: change) == echoRowPK {
        echoChangeID = change.changeID
      }
    }

    var durable: [DurablePendingChange] = []
    for change in changes where change.changeID != echoChangeID {
      guard let table = configuration.table(named: change.tableName) else { continue }
      durable.append(try durablePendingChange(for: change, table: table))
    }
    durable = coalescing(durable)
    try metadata.stagePendingChangesInCurrentTransaction(durable, through: last.changeID)
    return durable
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
      try discardPending(recordID: failedRecord.recordID, engine: engine)
    case .clientWins:
      try preserveClientRecord(serverRecord: serverRecord)
    case .lastWriterWins(let field):
      let local = try makeRecord(for: failedRecord.recordID)
      let localStamp = comparableStamp(local?[field])
      let serverStamp = comparableStamp(serverRecord[field])
      if let localStamp, let serverStamp, localStamp > serverStamp {
        guard let parsed = RecordIdentity.parse(failedRecord.recordID.recordName),
          !parsed.table.isEmpty, !parsed.rowPK.isEmpty
        else {
          // Cannot safely record meta without identity — re-apply server to stay consistent.
          try applyModification(serverRecord)
          return
        }
        try metadata.upsertRecordMeta(
          table: parsed.table,
          rowPK: parsed.rowPK,
          recordName: failedRecord.recordID.recordName,
          zoneName: zoneID.zoneName,
          systemFields: RecordMapper.encodeSystemFields(serverRecord)
        )
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(failedRecord.recordID)])
      } else {
        try applyModification(serverRecord)
        try discardPending(recordID: failedRecord.recordID, engine: engine)
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
      // Preserve local rows on account change; only clear sync metadata (OpenSpec).
      publishStatus(.accountChanged)
      try wipeAndRebootstrap(preserveLocalUserData: true)
    }

    if shouldReupload && !shouldWipe {
      if configuration.enablesCloudKit, let engine = try? requireEngine() {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
      }
      try enqueueAllLocalRows()
    }
  }

  /// Clears sync metadata and optionally user rows, then restarts the engine.
  ///
  /// - Parameter preserveLocalUserData: When `true` (account change), keep app tables and
  ///   re-upload rows. When `false` (zone deleted), wipe synced tables too.
  public func wipeAndRebootstrap(preserveLocalUserData: Bool = false) throws {
    try connection.withSynchronizingFlag {
      try connection.write {
        if !preserveLocalUserData {
          try RowSQL.deleteAllSyncedData(connection: connection, tables: configuration.syncedTables)
        }
        try metadata.wipeAll()
      }
    }
    lock.lock()
    syncEngine = nil
    localPendingRecordZoneChanges = []
    lock.unlock()
    try start()
    if preserveLocalUserData {
      try enqueueAllLocalRows()
    }
  }

  /// Splits current pending changes into CloudKit-sized batches (≤ ``maxBatchSize``).
  public func pendingBatches() -> [[CKSyncEngine.PendingRecordZoneChange]] {
    let pending = pendingRecordZoneChanges
    guard !pending.isEmpty else { return [] }
    let size = configuration.maxBatchSize
    var batches: [[CKSyncEngine.PendingRecordZoneChange]] = []
    var index = 0
    while index < pending.count {
      let end = min(index + size, pending.count)
      batches.append(Array(pending[index..<end]))
      index = end
    }
    return batches
  }

  /// Test hook: resolve a server/client conflict without the full CK send path.
  public func resolveConflictForTesting(
    failedRecord: CKRecord,
    serverRecord: CKRecord
  ) throws {
    switch configuration.conflictPolicy {
    case .serverWins:
      try applyModification(serverRecord)
      try discardPending(recordID: failedRecord.recordID)
    case .clientWins:
      try preserveClientRecord(serverRecord: serverRecord)
    case .lastWriterWins(let field):
      let local = try makeRecord(for: failedRecord.recordID)
      let localStamp = comparableStamp(local?[field])
      let serverStamp = comparableStamp(serverRecord[field])
      if let localStamp, let serverStamp, localStamp > serverStamp {
        if let parsed = RecordIdentity.parse(failedRecord.recordID.recordName) {
          try metadata.upsertRecordMeta(
            table: parsed.table,
            rowPK: parsed.rowPK,
            recordName: failedRecord.recordID.recordName,
            zoneName: zoneID.zoneName,
            systemFields: RecordMapper.encodeSystemFields(serverRecord)
          )
        }
        enqueuePending([.saveRecord(failedRecord.recordID)])
      } else {
        try applyModification(serverRecord)
        try discardPending(recordID: failedRecord.recordID)
      }
    }
  }

  private func enqueueAllLocalRows() throws {
    let cursor = try metadata.loadCDCCursor()
    var durable: [DurablePendingChange] = []
    for table in configuration.syncedTables {
      let rows = try connection.query(
        "SELECT \(RowSQL.quoteIdent(table.primaryKeyColumn)) AS pk FROM \(RowSQL.quoteIdent(table.name))"
      )
      for row in rows {
        guard let pk = row["pk"]?.stringValue ?? row["pk"]?.int64Value.map(String.init) else {
          continue
        }
        durable.append(
          DurablePendingChange(
            recordName: try table.recordName(forRowPK: pk),
            tableName: table.name,
            rowPK: pk,
            zoneName: zoneID.zoneName,
            operation: .save,
            changeID: cursor
          )
        )
      }
    }
    if !durable.isEmpty {
      try metadata.stagePendingChanges(durable, through: cursor)
      enqueueDurableChanges(durable)
    }
  }

  private func discardPending(recordID: CKRecord.ID, engine: CKSyncEngine? = nil) throws {
    try metadata.removePendingChange(recordName: recordID.recordName)
    let alternatives: [CKSyncEngine.PendingRecordZoneChange] = [
      .saveRecord(recordID), .deleteRecord(recordID),
    ]
    lock.lock()
    if let engine = engine ?? syncEngine {
      engine.state.remove(pendingRecordZoneChanges: alternatives)
    }
    localPendingRecordZoneChanges.removeAll { change in
      switch change {
      case .saveRecord(let id), .deleteRecord(let id): return id == recordID
      @unknown default: return false
      }
    }
    lock.unlock()
  }

  func acknowledgePendingChangeForTesting(recordID: CKRecord.ID) throws {
    try discardPending(recordID: recordID)
  }

  func recordForPendingSaveForTesting(recordID: CKRecord.ID) throws -> CKRecord? {
    try recordForPendingSave(recordID: recordID)
  }

  private func recordForPendingSave(
    recordID: CKRecord.ID,
    engine: CKSyncEngine? = nil
  ) throws -> CKRecord? {
    if let record = try makeRecord(for: recordID) {
      return record
    }
    try discardPending(recordID: recordID, engine: engine)
    return nil
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

  private func publishStatus(_ status: SyncStatus) {
    let sink: (@Sendable (SyncStatus) -> Void)?
    lock.lock()
    sink = _statusSink
    lock.unlock()
    sink?(status)
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
          // Zone gone — wipe local synced data and rebootstrap.
          try wipeAndRebootstrap(preserveLocalUserData: false)
        }

      case .fetchedRecordZoneChanges(let changes):
        publishStatus(.syncing)
        for modification in changes.modifications {
          try applyModification(modification.record)
        }
        for deletion in changes.deletions {
          try applyDeletion(deletion.recordID)
        }
        publishStatus(.idle)

      case .sentRecordZoneChanges(let sent):
        try handleSentRecordZoneChanges(sent, syncEngine: syncEngine)

      case .sentDatabaseChanges:
        zoneBootstrapped = true

      case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
        .didFetchChanges, .willSendChanges:
        publishStatus(.syncing)

      case .didSendChanges:
        publishStatus(.idle)

      @unknown default:
        logger.info("Unknown CKSyncEngine event")
      }
    } catch {
      logger.error("handleEvent failed: \(error.localizedDescription, privacy: .public)")
      publishStatus(.failed(error.localizedDescription))
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

    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) {
      [weak self] recordID in
      guard let self else { return nil }
      do {
        return try self.recordForPendingSave(recordID: recordID, engine: syncEngine)
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
      try metadata.removePendingChange(recordName: saved.recordID.recordName)
    }
    for deletedRecordID in event.deletedRecordIDs {
      try metadata.removePendingChange(recordName: deletedRecordID.recordName)
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
        logger.error(
          "Unhandled save failure: \(failure.error.localizedDescription, privacy: .public)"
        )
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
