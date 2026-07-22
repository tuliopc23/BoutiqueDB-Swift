import Foundation

/// Official Turso experimental feature tokens
/// (`docs/sql-reference/experimental-features.mdx`).
public enum TursoExperimentalFeature: String, Sendable, Hashable, CaseIterable {
  case views
  case customTypes = "custom_types"
  case encryption
  case indexMethod = "index_method"
  case autovacuum
  case vacuum
  case attach
  case generatedColumns = "generated_columns"
  case withoutRowid = "without_rowid"
  case multiprocessWAL = "multiprocess_wal"
  case mvccPassiveCheckpoint = "mvcc_passive_checkpoint"
}

/// Open configuration for the official sdk-kit C ABI (`turso_database_config_t`).
///
/// Experimental features are **opt-in**. Do not enable flags not listed in Turso docs.
public struct TursoOpenOptions: Sendable, Equatable {
  /// Official CSV tokens passed as `experimental_features`.
  public var experimentalFeatures: Set<TursoExperimentalFeature>
  /// When true, sets official `async_io` and TursoKit drives `TURSO_IO` with
  /// `await Task.yield()` (cooperative with Swift concurrency).
  public var asyncIO: Bool
  /// Optional VFS: `nil` (default), `"memory"`, `"syscall"`, …
  public var vfs: String?
  /// Engine encryption (requires `encryption` feature in the set + build with encryption).
  public var encryptionCipher: String?
  public var encryptionHexKey: String?

  public init(
    experimentalFeatures: Set<TursoExperimentalFeature> = [],
    asyncIO: Bool = false,
    vfs: String? = nil,
    encryptionCipher: String? = nil,
    encryptionHexKey: String? = nil
  ) {
    self.experimentalFeatures = experimentalFeatures
    self.asyncIO = asyncIO
    self.vfs = vfs
    self.encryptionCipher = encryptionCipher
    self.encryptionHexKey = encryptionHexKey
  }

  /// Curated preset for search/views (no encryption / multi-process).
  public static let tursoEnhanced = TursoOpenOptions(
    experimentalFeatures: [
      .views, .indexMethod, .generatedColumns, .vacuum, .withoutRowid,
    ],
    asyncIO: false
  )

  /// ``tursoEnhanced`` experimental flags + cooperative `async_io`.
  public static let tursoEnhancedAsync = TursoOpenOptions(
    experimentalFeatures: [
      .views, .indexMethod, .generatedColumns, .vacuum, .withoutRowid,
    ],
    asyncIO: true
  )

  public var experimentalFeaturesCSV: String? {
    let tokens = experimentalFeatures.map(\.rawValue).sorted()
    return tokens.isEmpty ? nil : tokens.joined(separator: ",")
  }

  public mutating func insert(_ feature: TursoExperimentalFeature) {
    experimentalFeatures.insert(feature)
  }
}
