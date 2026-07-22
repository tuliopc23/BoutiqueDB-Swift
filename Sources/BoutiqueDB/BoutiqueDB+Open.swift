import Foundation

extension BoutiqueDB {
  /// Seamless open: connect, apply migrations, optional additive schema sync.
  ///
  /// ```swift
  /// let db = try await BoutiqueDB.open(
  ///   url: supportURL,
  ///   migrations: AppMigrations.plan
  /// )
  /// ```
  public static func open(
    url: URL,
    startListening: Bool = true,
    enableCDC: Bool = true,
    concurrentWrites: Bool = false,
    migrations: BoutiqueMigrationPlan? = nil,
    schemaModels: [any BoutiqueSchema.Type] = [],
    schemaSync: SchemaSyncPolicy = .off
  ) async throws -> BoutiqueDB {
    let db = try BoutiqueDB(
      url: url,
      startListening: startListening,
      enableCDC: enableCDC,
      concurrentWrites: concurrentWrites
    )

    if let migrations {
      let migrator = BoutiqueMigrator()
      do {
        _ = try await migrator.migrate(db: db, plan: migrations)
      } catch let error as BoutiqueError {
        if case .schemaErasedForDebug = error {
          // File wiped — open a fresh handle and re-apply.
          let fresh = try BoutiqueDB(
            url: url,
            startListening: startListening,
            enableCDC: enableCDC,
            concurrentWrites: concurrentWrites
          )
          _ = try await BoutiqueMigrator().migrate(db: fresh, plan: migrations)
          if schemaSync != .off, !schemaModels.isEmpty {
            try await fresh.syncSchema(schemaModels, policy: schemaSync)
          }
          return fresh
        }
        throw error
      }
    }

    if schemaSync != .off, !schemaModels.isEmpty {
      try await db.syncSchema(schemaModels, policy: schemaSync)
    }
    return db
  }

  /// Apply a migration plan to an already-open database.
  @discardableResult
  public func migrate(using plan: BoutiqueMigrationPlan) async throws -> [String] {
    try await BoutiqueMigrator().migrate(db: self, plan: plan)
  }

  /// IDs already recorded in `boutique_schema_migrations`.
  public func appliedMigrations() async throws -> [String] {
    try await BoutiqueMigrator().appliedIdentifiers(on: self)
  }
}
