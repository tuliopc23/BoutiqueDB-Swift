import StructuredQueriesCore
import TursoKit

extension StructuredQueriesCore.Table where QueryOutput: Sendable {
  public static func fetchAll(_ db: TursoConnection) async throws -> [QueryOutput] {
    try await all.fetchAll(db)
  }

  public static func fetchOne(_ db: TursoConnection) async throws -> QueryOutput? {
    try await all.fetchOne(db)
  }

  public static func fetchCount(_ db: TursoConnection) async throws -> Int {
    try await all.fetchCount(db)
  }
}

extension StructuredQueriesCore.PrimaryKeyedTable where QueryOutput: Sendable {
  public static func find(
    _ db: TursoConnection,
    key primaryKey: some QueryExpression<PrimaryKey>
  ) async throws -> QueryOutput {
    try await all.find(db, key: primaryKey)
  }
}
