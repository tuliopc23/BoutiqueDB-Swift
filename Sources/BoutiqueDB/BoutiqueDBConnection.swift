import Foundation
import StructuredQueries
import StructuredQueriesTurso
import TursoKit

/// A lightweight handle to the current transaction inside a ``BoutiqueDB``
/// read or write block.
public struct BoutiqueDBConnection {
  public let connection: TursoConnection

  public init(_ connection: TursoConnection) {
    self.connection = connection
  }

  public func execute(_ sql: String, _ bindings: [TursoValue] = []) throws {
    try connection.execute(sql, bindings)
  }

  public func query(
    _ sql: String,
    _ bindings: [TursoValue] = []
  ) throws -> [[String: TursoValue]] {
    try connection.query(sql, bindings)
  }

  public func queryOne(
    _ sql: String,
    _ bindings: [TursoValue] = []
  ) throws -> [String: TursoValue]? {
    try connection.queryOne(sql, bindings)
  }

  public func fetchAll<T: Table>(
    _ table: T.Type
  ) throws -> [T.QueryOutput] where T == T.QueryOutput {
    try T.all.fetchAll(connection)
  }

  public func fetchCount<T: Table>(
    _ table: T.Type
  ) throws -> Int where T == T.QueryOutput {
    try T.all.fetchCount(connection)
  }

  /// Returns the row for `key`, or `nil` if it does not exist.
  ///
  /// SQL and decode failures **throw** (they are not swallowed as `nil`).
  public func fetchOne<T: PrimaryKeyedTable>(
    _ table: T.Type,
    key: T.PrimaryKey
  ) throws -> T.QueryOutput? where T == T.QueryOutput {
    try T.find(key).fetchOne(connection)
  }
}
