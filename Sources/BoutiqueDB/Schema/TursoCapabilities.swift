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

  public static let unknown = TursoCapabilities(
    cdc: false,
    mvcc: false,
    ftsIndex: false,
    vectorFunctions: false,
    vectorIndex: false,
    materializedViews: false,
    encryption: false,
    multiProcessWAL: false,
    generatedColumns: false
  )

  /// Probe a live connection with cheap SQL capability checks.
  public static func probe(on connection: TursoConnection) -> TursoCapabilities {
    var caps = TursoCapabilities.unknown
    caps.cdc = probeCDC(on: connection)
    caps.generatedColumns = true
    caps.multiProcessWAL = false  // BD-004 — requires Builder / C setter
    caps.encryption = false  // BD-001 — C open path does not wire cipher yet

    caps.vectorFunctions =
      (try? connection.queryOne("SELECT vector32('[1.0,0.0]') IS NOT NULL AS ok")?["ok"]?
        .int64Value) == 1

    caps.ftsIndex = probeFTS(on: connection)
    caps.vectorIndex = probeVectorIndex(on: connection)
    caps.materializedViews = probeMaterializedView(on: connection)
    caps.mvcc = probeMVCC(on: connection)
    // Do not claim encryption from PRAGMA alone when open path cannot set keys.
    _ = probeEncryption(on: connection)

    return caps
  }

  private static func probeCDC(on connection: TursoConnection) -> Bool {
    do {
      // Shared CDC table exists after enableCaptureDataChanges, or accept pragma.
      try connection.execute("SAVEPOINT boutique_cdc_probe")
      defer {
        try? connection.execute("ROLLBACK TO boutique_cdc_probe")
        try? connection.execute("RELEASE boutique_cdc_probe")
      }
      // If already enabled on this connection, turso_cdc is queryable.
      if (try? connection.queryOne("SELECT 1 AS ok FROM sqlite_master WHERE name = 'turso_cdc'"))
        != nil
      {
        return true
      }
      try connection.execute("PRAGMA capture_data_changes_conn('id')")
      let ok =
        (try? connection.queryOne(
          "SELECT 1 AS ok FROM sqlite_master WHERE name = 'turso_cdc'"
        )) != nil
      try connection.execute("PRAGMA capture_data_changes_conn('off')")
      return ok
    } catch {
      return false
    }
  }

  private static func probeFTS(on connection: TursoConnection) -> Bool {
    do {
      try connection.execute("SAVEPOINT boutique_fts")
      defer {
        try? connection.execute("ROLLBACK TO boutique_fts")
        try? connection.execute("RELEASE boutique_fts")
      }
      try connection.execute("CREATE TEMP TABLE __boutique_fts_t (title TEXT)")
      try connection.execute(
        "CREATE INDEX __boutique_fts_i ON __boutique_fts_t USING fts(title)"
      )
      return true
    } catch {
      return false
    }
  }

  private static func probeVectorIndex(on connection: TursoConnection) -> Bool {
    do {
      try connection.execute("SAVEPOINT boutique_vec")
      defer {
        try? connection.execute("ROLLBACK TO boutique_vec")
        try? connection.execute("RELEASE boutique_vec")
      }
      try connection.execute("CREATE TEMP TABLE __boutique_vec_t (embedding BLOB)")
      try connection.execute(
        "CREATE INDEX __boutique_vec_i ON __boutique_vec_t USING vector(embedding)"
      )
      return true
    } catch {
      return false
    }
  }

  private static func probeMaterializedView(on connection: TursoConnection) -> Bool {
    do {
      try connection.execute("SAVEPOINT boutique_mv")
      defer {
        try? connection.execute("ROLLBACK TO boutique_mv")
        try? connection.execute("RELEASE boutique_mv")
      }
      try connection.execute(
        "CREATE TEMP TABLE __boutique_mv_base (id INTEGER, n INTEGER)"
      )
      try connection.execute(
        """
        CREATE MATERIALIZED VIEW __boutique_mv AS
        SELECT id, SUM(n) AS total FROM __boutique_mv_base GROUP BY id
        """
      )
      return true
    } catch {
      return false
    }
  }

  private static func probeMVCC(on connection: TursoConnection) -> Bool {
    do {
      try connection.execute("SAVEPOINT boutique_mvcc")
      defer {
        try? connection.execute("ROLLBACK TO boutique_mvcc")
        try? connection.execute("RELEASE boutique_mvcc")
      }
      try connection.execute("BEGIN CONCURRENT")
      try connection.execute("ROLLBACK")
      return true
    } catch {
      return false
    }
  }

  private static func probeEncryption(on connection: TursoConnection) -> Bool {
    do {
      _ = try connection.query("PRAGMA hexkey")
      return true
    } catch {
      return false
    }
  }
}
