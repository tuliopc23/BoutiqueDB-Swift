import Foundation
import StructuredQueries
import StructuredQueriesTurso
import TursoKit

/// A lightweight handle to the current transaction inside a ``BoutiqueDB``
/// read or write block.
public struct BoutiqueDBConnection: Sendable {
  public let connection: TursoConnection

  public init(_ connection: TursoConnection) {
    self.connection = connection
  }

  public func execute(_ sql: String, _ bindings: [TursoValue] = []) async throws {
    try await connection.execute(sql, bindings)
  }

  public func query(
    _ sql: String,
    _ bindings: [TursoValue] = []
  ) async throws -> [[String: TursoValue]] {
    try await connection.query(sql, bindings)
  }

  public func queryOne(
    _ sql: String,
    _ bindings: [TursoValue] = []
  ) async throws -> [String: TursoValue]? {
    try await connection.queryOne(sql, bindings)
  }

  public func fetchAll<T: Table & Sendable>(
    _ table: T.Type
  ) async throws -> [T.QueryOutput] where T == T.QueryOutput {
    try await T.all.fetchAll(connection)
  }

  public func fetchCount<T: Table & Sendable>(
    _ table: T.Type
  ) async throws -> Int where T == T.QueryOutput {
    try await T.all.fetchCount(connection)
  }

  /// Returns the row for `key`, or `nil` if it does not exist.
  ///
  /// SQL and decode failures **throw** (they are not swallowed as `nil`).
  public func fetchOne<T: PrimaryKeyedTable & Sendable>(
    _ table: T.Type,
    key: T.PrimaryKey
  ) async throws -> T.QueryOutput? where T == T.QueryOutput, T.PrimaryKey: Sendable {
    try await T.find(key).fetchOne(connection)
  }
}
