import Foundation
import TursoKit

/// Runtime probe of Turso features that stock SQLite does not provide.
///
/// Used to gate FTS/vector indexes, materialized views, encryption, and MVCC so
/// Apple apps get clear errors instead of opaque SQL failures.
public struct TursoCapabilities: Sendable, Equatable {
  public var cdc: Bool
  public var mvcc: Bool
  public var ftsIndex: Bool
  public var vectorFunctions: Bool
  public var vectorIndex: Bool
  public var materializedViews: Bool
  public var encryption: Bool
  public var multiProcessWAL: Bool
  public var generatedColumns: Bool
  public var customTypes: Bool

  public static let unknown = TursoCapabilities(
    cdc: false,
    mvcc: false,
    ftsIndex: false,
    vectorFunctions: false,
    vectorIndex: false,
    materializedViews: false,
    encryption: false,
    multiProcessWAL: false,
    generatedColumns: false,
    customTypes: false
  )

  /// Probe a live connection with cheap SQL capability checks.
  public static func probe(on connection: TursoConnection) async -> TursoCapabilities {
    var caps = TursoCapabilities.unknown
    let database = await connection.database
    let options = database?.openOptions
    caps.cdc = await probeCDC(on: connection)
    caps.generatedColumns = options?.experimentalFeatures.contains(.generatedColumns) == true
    caps.customTypes = options?.experimentalFeatures.contains(.customTypes) == true
    caps.multiProcessWAL = options?.experimentalFeatures.contains(.multiprocessWAL) == true
    caps.encryption =
      options?.experimentalFeatures.contains(.encryption) == true
      && options?.encryptionCipher?.isEmpty == false
      && options?.encryptionHexKey?.isEmpty == false

    caps.vectorFunctions =
      (try? await connection.queryOne("SELECT vector32('[1.0,0.0]') IS NOT NULL AS ok")?["ok"]?
        .int64Value) == 1

    caps.ftsIndex = await probeFTS(on: connection)
    caps.vectorIndex = await probeVectorIndex(on: connection)
    caps.materializedViews = await probeMaterializedView(on: connection)
    caps.mvcc = await probeMVCC(on: connection)

    return caps
  }

  private static func probeCDC(on connection: TursoConnection) async -> Bool {
    // Capability inspection must never opt a connection into CDC as a side effect.
    (try? await connection.queryOne(
      "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'turso_cdc'"
    )) != nil
  }

  private static func probeMVCC(on connection: TursoConnection) async -> Bool {
    guard let row = try? await connection.queryOne("PRAGMA journal_mode") else { return false }
    return row.values.contains { $0.stringValue?.lowercased() == "mvcc" }
  }

  private static func probeFTS(on connection: TursoConnection) async -> Bool {
    do {
      try await connection.execute("SAVEPOINT boutique_fts")
      try await connection.execute("CREATE TEMP TABLE __boutique_fts_t (title TEXT)")
      try await connection.execute(
        "CREATE INDEX __boutique_fts_i ON __boutique_fts_t USING fts(title)"
      )
    } catch {
      try? await connection.execute("ROLLBACK TO boutique_fts")
      try? await connection.execute("RELEASE boutique_fts")
      return false
    }
    try? await connection.execute("ROLLBACK TO boutique_fts")
    try? await connection.execute("RELEASE boutique_fts")
    return true
  }

  private static func probeVectorIndex(on connection: TursoConnection) async -> Bool {
    do {
      try await connection.execute("SAVEPOINT boutique_vec")
      try await connection.execute("CREATE TEMP TABLE __boutique_vec_t (embedding BLOB)")
      try await connection.execute(
        "CREATE INDEX __boutique_vec_i ON __boutique_vec_t USING vector(embedding)"
      )
    } catch {
      try? await connection.execute("ROLLBACK TO boutique_vec")
      try? await connection.execute("RELEASE boutique_vec")
      return false
    }
    try? await connection.execute("ROLLBACK TO boutique_vec")
    try? await connection.execute("RELEASE boutique_vec")
    return true
  }

  private static func probeMaterializedView(on connection: TursoConnection) async -> Bool {
    do {
      try await connection.execute("SAVEPOINT boutique_mv")
      try await connection.execute(
        "CREATE TEMP TABLE __boutique_mv_base (id INTEGER, n INTEGER)"
      )
      try await connection.execute(
        """
        CREATE MATERIALIZED VIEW __boutique_mv AS
        SELECT id, SUM(n) AS total FROM __boutique_mv_base GROUP BY id
        """
      )
    } catch {
      try? await connection.execute("ROLLBACK TO boutique_mv")
      try? await connection.execute("RELEASE boutique_mv")
      return false
    }
    try? await connection.execute("ROLLBACK TO boutique_mv")
    try? await connection.execute("RELEASE boutique_mv")
    return true
  }

}
