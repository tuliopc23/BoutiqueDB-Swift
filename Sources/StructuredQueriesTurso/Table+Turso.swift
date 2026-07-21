import StructuredQueriesCore
import TursoKit

extension StructuredQueriesCore.Table {
  public static func fetchAll(_ db: TursoConnection) throws -> [QueryOutput] {
    try all.fetchAll(db)
  }

  public static func fetchOne(_ db: TursoConnection) throws -> QueryOutput? {
    try all.fetchOne(db)
  }

  public static func fetchCount(_ db: TursoConnection) throws -> Int {
    try all.fetchCount(db)
  }
}

extension StructuredQueriesCore.PrimaryKeyedTable {
  public static func find(
    _ db: TursoConnection,
    key primaryKey: some QueryExpression<PrimaryKey>
  ) throws -> QueryOutput {
    try all.find(db, key: primaryKey)
  }
}
