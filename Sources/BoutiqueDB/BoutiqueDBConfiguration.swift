import Foundation
import TursoKit

/// The complete, reusable bootstrap configuration for a BoutiqueDB store.
///
/// Keep one value in the app composition root so previews, tests, migrations,
/// debug erasure, and production startup cannot silently choose different
/// engine options.
public struct BoutiqueDBConfiguration: Sendable {
  public var url: URL
  public var startListening: Bool
  public var enableCDC: Bool
  public var concurrentWrites: Bool
  public var openOptions: TursoOpenOptions
  public var encryption: EncryptionConfig?
  public var multiProcess: Bool
  public var migrations: BoutiqueMigrationPlan?
  public var schemaModels: [any BoutiqueSchema.Type]
  public var schemaSync: SchemaSyncPolicy

  public init(
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
  ) {
    self.url = url
    self.startListening = startListening
    self.enableCDC = enableCDC
    self.concurrentWrites = concurrentWrites
    self.openOptions = openOptions
    self.encryption = encryption
    self.multiProcess = multiProcess
    self.migrations = migrations
    self.schemaModels = schemaModels
    self.schemaSync = schemaSync
  }
}
