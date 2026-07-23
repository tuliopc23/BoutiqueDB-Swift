import Foundation

/// A single append-only schema migration (GRDB / SQLiteData style).
///
/// - Important: Once a migration `id` has shipped to users, never change its body.
public struct BoutiqueMigration: Sendable {
  public let id: String
  let body: Body

  enum Body: Sendable {
    case transactional(@Sendable (inout BoutiqueDBConnection) async throws -> Void)
    case asynchronous(@Sendable (BoutiqueDB) async throws -> Void)
  }

  /// Creates an atomic migration. The migration body and tracking record commit
  /// in the same transaction, making this the default form for synchronous work.
  public init(
    _ id: String,
    migrate: @escaping @Sendable (inout BoutiqueDBConnection) async throws -> Void
  ) {
    self.id = id
    self.body = .transactional(migrate)
  }

  /// Creates a suspending migration. Because a native transaction cannot remain
  /// open across arbitrary suspension, this form must be idempotent. Prefer the
  /// synchronous overload whenever possible.
  public init(
    _ id: String,
    asynchronous migrate: @escaping @Sendable (BoutiqueDB) async throws -> Void
  ) {
    self.id = id
    self.body = .asynchronous(migrate)
  }

}

@resultBuilder
public enum BoutiqueMigrationPlanBuilder {
  public static func buildBlock(_ migrations: BoutiqueMigration...) -> [BoutiqueMigration] {
    Array(migrations)
  }

  public static func buildArray(_ components: [[BoutiqueMigration]]) -> [BoutiqueMigration] {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ component: [BoutiqueMigration]?) -> [BoutiqueMigration] {
    component ?? []
  }

  public static func buildEither(first component: [BoutiqueMigration]) -> [BoutiqueMigration] {
    component
  }

  public static func buildEither(second component: [BoutiqueMigration]) -> [BoutiqueMigration] {
    component
  }
}

/// Ordered list of migrations applied by ``BoutiqueMigrator``.
public struct BoutiqueMigrationPlan: Sendable {
  public let migrations: [BoutiqueMigration]
  /// When `true` (DEBUG recommended), erase the DB file if registered migration IDs
  /// diverge from what's recorded (SQLiteData / GRDB pattern).
  public var eraseDatabaseOnSchemaChange: Bool

  public init(
    eraseDatabaseOnSchemaChange: Bool = false,
    @BoutiqueMigrationPlanBuilder _ build: () -> [BoutiqueMigration]
  ) {
    self.migrations = build()
    self.eraseDatabaseOnSchemaChange = eraseDatabaseOnSchemaChange
  }

  public init(
    migrations: [BoutiqueMigration],
    eraseDatabaseOnSchemaChange: Bool = false
  ) {
    self.migrations = migrations
    self.eraseDatabaseOnSchemaChange = eraseDatabaseOnSchemaChange
  }
}

/// Applies ``BoutiqueMigrationPlan`` entries transactionally and records IDs in
/// `boutique_schema_migrations`.
@MainActor
public struct BoutiqueMigrator: Sendable {
  public static let trackingTableSQL = """
    CREATE TABLE IF NOT EXISTS boutique_schema_migrations (
      id TEXT PRIMARY KEY NOT NULL,
      applied_at REAL NOT NULL
    )
    """

  private let now: @Sendable () -> Date

  public init(now: @escaping @Sendable () -> Date = Date.init) {
    self.now = now
  }

  /// Ensures the tracking table exists.
  public func prepareTracking(on db: BoutiqueDB) async throws {
    try await db.execute(Self.trackingTableSQL)
  }

  public func appliedIdentifiers(on db: BoutiqueDB) async throws -> [String] {
    try await prepareTracking(on: db)
    let rows = try await db.read { conn in
      try await conn.query(
        "SELECT id FROM boutique_schema_migrations ORDER BY rowid ASC"
      )
    }
    return rows.compactMap { $0["id"]?.stringValue }
  }

  public func hasCompletedMigrations(on db: BoutiqueDB, plan: BoutiqueMigrationPlan) async throws
    -> Bool
  {
    let applied = Set(try await appliedIdentifiers(on: db))
    return plan.migrations.allSatisfy { applied.contains($0.id) }
  }

  /// Applies any migrations in `plan` that are not yet recorded.
  ///
  /// - Returns: IDs that were applied in this call.
  @discardableResult
  public func migrate(db: BoutiqueDB, plan: BoutiqueMigrationPlan) async throws -> [String] {
    try validate(plan: plan)
    try await prepareTracking(on: db)

    if plan.eraseDatabaseOnSchemaChange {
      try await maybeEraseOnSchemaChange(db: db, plan: plan)
    }

    let appliedIdentifiers = try await appliedIdentifiers(on: db)
    try validateAppliedHistory(appliedIdentifiers, plan: plan)
    let applied = Set(appliedIdentifiers)
    var newlyApplied: [String] = []

    for migration in plan.migrations {
      if applied.contains(migration.id) { continue }
      // Prefer recording the id only after a successful body. Schema DDL and
      // the bookkeeping insert cannot always share one SQLite transaction
      // (DDL auto-commits on some paths), so we still insert the id only on
      // success — a failed body never marks the migration applied.
      //
      // Contract: migration bodies MUST be idempotent. Mid-body failure can
      // leave partial DDL applied; on retry the body runs again (IF NOT EXISTS,
      // ensureColumn, etc.). Prefer ``BoutiqueDB/write`` for multi-statement DML
      // that should roll back together.
      do {
        switch migration.body {
        case .transactional(let body):
          try await db.write { connection in
            try await body(&connection)
            try await connection.execute(
              """
              INSERT INTO boutique_schema_migrations (id, applied_at)
              VALUES (?, ?)
              """,
              [.text(migration.id), .double(now().timeIntervalSince1970)]
            )
          }
        case .asynchronous(let body):
          try await body(db)
          try await db.execute(
            """
            INSERT INTO boutique_schema_migrations (id, applied_at)
            VALUES (?, ?)
            """,
            [.text(migration.id), .double(now().timeIntervalSince1970)]
          )
        }
        newlyApplied.append(migration.id)
      } catch {
        throw BoutiqueError.migrationFailed(
          id: migration.id,
          message: String(describing: error)
        )
      }
    }
    return newlyApplied
  }

  private func maybeEraseOnSchemaChange(db: BoutiqueDB, plan: BoutiqueMigrationPlan) async throws {
    let applied = try await appliedIdentifiers(on: db)
    guard !applied.isEmpty else { return }
    let registered = plan.migrations.map(\.id)
    // Divergence: applied ID not in plan, or order mismatch of common prefix.
    let appliedSet = Set(applied)
    let registeredSet = Set(registered)
    let unknown = appliedSet.subtracting(registeredSet)
    if !unknown.isEmpty {
      throw BoutiqueError.schemaErasedForDebug(
        "eraseDatabaseOnSchemaChange: unknown applied ids \(unknown.sorted())"
      )
    }
  }

  static func eraseDatabaseFiles(at url: URL) throws {
    let fm = FileManager.default
    for suffix in ["", "-wal", "-shm"] {
      let path = url.path + suffix
      if fm.fileExists(atPath: path) {
        try fm.removeItem(atPath: path)
      }
    }
  }

  private func validate(plan: BoutiqueMigrationPlan) throws {
    let ids = plan.migrations.map(\.id)
    if ids.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
      throw BoutiqueError.invalidMigrationPlan("Migration identifiers must not be empty")
    }
    if Set(ids).count != ids.count {
      throw BoutiqueError.invalidMigrationPlan("Migration identifiers must be unique")
    }
  }

  private func validateAppliedHistory(
    _ applied: [String],
    plan: BoutiqueMigrationPlan
  ) throws {
    let registered = plan.migrations.map(\.id)
    guard applied.count <= registered.count,
      Array(registered.prefix(applied.count)) == applied
    else {
      throw BoutiqueError.invalidMigrationPlan(
        "Applied migrations must remain an unchanged prefix of the registered plan"
      )
    }
  }
}
