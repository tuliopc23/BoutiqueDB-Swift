import Foundation
import TursoKit

/// High-level errors thrown by ``BoutiqueDB`` and related framework APIs.
public enum BoutiqueError: Error, Sendable, Equatable {
  /// CDC and MVCC cannot be enabled on the same connection handle (BD-005).
  case cdcMutuallyExclusiveWithMVCC

  /// At-rest encryption was requested but the vendored engine does not expose it.
  case encryptionUnavailable

  /// Multi-process WAL was requested but is not available on this build.
  case multiProcessWALUnavailable

  /// A Turso feature is not available in the current `libturso_sqlite3` build.
  case featureUnavailable(String)

  /// Underlying engine / SQL failure.
  case sql(code: Int32, message: String)

  /// The database connection is closed.
  case closed

  /// DEBUG migrator erased the database file due to schema-change policy.
  /// Re-open the database and re-run migrations.
  case schemaErasedForDebug(String)

  /// Migration failed.
  case migrationFailed(id: String, message: String)

  /// A concurrent or exclusive transaction is already open on this actor.
  case transactionInProgress

  /// Nested begin / invalid transaction state.
  case invalidTransactionState(String)
}

extension BoutiqueError {
  public static func sql(_ error: TursoError) -> BoutiqueError {
    .sql(code: error.code, message: error.message)
  }
}
