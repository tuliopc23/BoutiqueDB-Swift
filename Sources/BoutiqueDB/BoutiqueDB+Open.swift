import Foundation
import TursoKit

extension BoutiqueDB {
  /// Opens a fully configured store, applies migrations/schema, then starts observation.
  public static func open(_ configuration: BoutiqueDBConfiguration) async throws -> BoutiqueDB {
    let db = try BoutiqueDB(
      url: configuration.url,
      startListening: false,
      enableCDC: configuration.enableCDC,
      concurrentWrites: configuration.concurrentWrites,
      openOptions: configuration.openOptions,
      encryption: configuration.encryption,
      multiProcess: configuration.multiProcess
    )

    if let migrations = configuration.migrations {
      let migrator = BoutiqueMigrator()
      do {
        _ = try await migrator.migrate(db: db, plan: migrations)
      } catch let error as BoutiqueError {
        if case .schemaErasedForDebug = error {
          db.close()
          try BoutiqueMigrator.eraseDatabaseFiles(at: configuration.url)
          var freshConfiguration = configuration
          freshConfiguration.startListening = false
          freshConfiguration.migrations = nil
          freshConfiguration.schemaModels = []
          freshConfiguration.schemaSync = .off
          let fresh = try BoutiqueDB(configuration: freshConfiguration)
          _ = try await BoutiqueMigrator().migrate(db: fresh, plan: migrations)
          if configuration.schemaSync != .off, !configuration.schemaModels.isEmpty {
            try await fresh.syncSchema(
              configuration.schemaModels,
              policy: configuration.schemaSync
            )
          }
          if configuration.startListening { fresh.store.startListening() }
          return fresh
        }
        db.close()
        throw error
      }
    }

    do {
      if configuration.schemaSync != .off, !configuration.schemaModels.isEmpty {
        try await db.syncSchema(configuration.schemaModels, policy: configuration.schemaSync)
      }
    } catch {
      db.close()
      throw error
    }
    if configuration.startListening { db.store.startListening() }
    return db
  }

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
    openOptions: TursoOpenOptions = .tursoEnhanced,
    encryption: EncryptionConfig? = nil,
    multiProcess: Bool = false,
    migrations: BoutiqueMigrationPlan? = nil,
    schemaModels: [any BoutiqueSchema.Type] = [],
    schemaSync: SchemaSyncPolicy = .off
  ) async throws -> BoutiqueDB {
    try await open(
      BoutiqueDBConfiguration(
        url: url,
        startListening: startListening,
        enableCDC: enableCDC,
        concurrentWrites: concurrentWrites,
        openOptions: openOptions,
        encryption: encryption,
        multiProcess: multiProcess,
        migrations: migrations,
        schemaModels: schemaModels,
        schemaSync: schemaSync
      )
    )
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
