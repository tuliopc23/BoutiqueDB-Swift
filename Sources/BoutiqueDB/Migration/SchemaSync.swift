import Foundation

/// Controls optional lightweight (additive-only) schema synchronization.
public enum SchemaSyncPolicy: Sendable, Equatable {
  /// Do nothing beyond explicit migrations.
  case off
  /// Create missing `BoutiqueSchema` tables/indexes (`CREATE IF NOT EXISTS` only).
  /// Never drops or renames. Intended for DEBUG iteration and careful opt-in.
  case additiveOnly
}

extension BoutiqueDB {
  /// Applies additive schema sync for the given models.
  ///
  /// - Creates missing tables/indexes via ``create(_:)`` / IF NOT EXISTS DDL.
  /// - Ensures columns for types conforming to ``BoutiqueSchemaColumns``.
  /// - Never drops or renames anything.
  public func syncSchema(
    _ schemas: [any BoutiqueSchema.Type],
    policy: SchemaSyncPolicy
  ) async throws {
    guard policy != .off else { return }
    for schema in schemas {
      let statements = schema.boutiqueCreateStatements
      if !statements.isEmpty {
        // Prefer full create path (capability-gated) when statements present.
        do {
          try await create(schema)
        } catch let error as BoutiqueError {
          // Capability missing for FTS/vector is non-fatal during additive sync:
          // still try plain CREATE TABLE statements if any.
          if case .featureUnavailable = error {
            for sql in statements where !sql.uppercased().contains("USING FTS")
              && !sql.uppercased().contains("USING VECTOR")
              && !sql.uppercased().contains("MATERIALIZED VIEW")
            {
              try await execute(sql)
            }
          } else {
            throw error
          }
        }
      }
      // Additive columns (R0.6 / A-009).
      if let columnsType = schema as? any BoutiqueSchemaColumns.Type {
        let table = columnsType.boutiqueTableName
        for col in columnsType.boutiqueColumns {
          try await ensureColumn(
            table: table,
            name: col.name,
            sqlType: col.sqlType,
            default: col.defaultSQL
          )
        }
      }
    }
  }
}
