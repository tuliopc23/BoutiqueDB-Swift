import Foundation
import StructuredQueriesCore
import TursoKit

extension StructuredQueriesCore.Statement {
  /// Executes a structured query (INSERT/UPDATE/DELETE) on a Turso connection.
  public func execute(_ db: TursoConnection) throws where QueryValue == () {
    try db.run(query: query) { statement in
      _ = try statement.step()
    }
  }

  /// Returns all decoded rows for a structured query.
  public func fetchAll(_ db: TursoConnection) throws -> [QueryValue.QueryOutput]
  where QueryValue: QueryRepresentable {
    try db.run(query: query) { statement in
      var decoder = TursoQueryDecoder(statement: statement)
      var results: [QueryValue.QueryOutput] = []
      while try statement.step() {
        results.append(try QueryValue(decoder: &decoder).queryOutput)
        decoder.next()
      }
      return results
    }
  }

  /// Returns the first decoded row, if any.
  public func fetchOne(_ db: TursoConnection) throws -> QueryValue.QueryOutput?
  where QueryValue: QueryRepresentable {
    try fetchAll(db).first
  }
}

extension StructuredQueriesCore.Statement {
  public func fetchAll<each Value: QueryRepresentable>(
    _ db: TursoConnection
  ) throws -> [(repeat (each Value).QueryOutput)]
  where QueryValue == (repeat each Value) {
    try db.run(query: query) { statement in
      var decoder = TursoQueryDecoder(statement: statement)
      var results: [(repeat (each Value).QueryOutput)] = []
      while try statement.step() {
        results.append(try decoder.decodeColumns((repeat each Value).self))
        decoder.next()
      }
      return results
    }
  }

  public func fetchOne<each Value: QueryRepresentable>(
    _ db: TursoConnection
  ) throws -> (repeat (each Value).QueryOutput)?
  where QueryValue == (repeat each Value) {
    try fetchAll(db).first
  }
}

extension SelectStatement where QueryValue == (), Joins == () {
  public func fetchAll(_ db: TursoConnection) throws -> [From.QueryOutput] {
    try db.run(query: query) { statement in
      var decoder = TursoQueryDecoder(statement: statement)
      var results: [From.QueryOutput] = []
      while try statement.step() {
        results.append(try From(decoder: &decoder).queryOutput)
        decoder.next()
      }
      return results
    }
  }

  public func fetchOne(_ db: TursoConnection) throws -> From.QueryOutput? {
    try asSelect().limit(1).fetchAll(db).first
  }

  public func fetchCount(_ db: TursoConnection) throws -> Int {
    try asSelect().count().fetchOne(db) ?? 0
  }
}

extension SelectStatement where QueryValue == (), From: PrimaryKeyedTable, Joins == () {
  public func find(
    _ db: TursoConnection,
    key primaryKey: some QueryExpression<From.PrimaryKey>
  ) throws -> From.QueryOutput {
    guard let record = try asSelect().find(primaryKey).fetchOne(db) else {
      throw TursoError(code: -1, message: "Record not found")
    }
    return record
  }
}

extension TursoConnection {
  func run<T>(query: QueryFragment, body: (TursoStatement) throws -> T) throws -> T {
    guard !query.isEmpty else {
      throw TursoError(code: -1, message: "Empty query fragment")
    }
    let (sql, bindings) = query.prepare { _ in "?" }
    return try withPreparedStatement(sql) { statement in
      try Self.bind(bindings, to: statement)
      return try body(statement)
    }
  }

  private static func bind(_ bindings: [QueryBinding], to statement: TursoStatement) throws {
    for (offset, binding) in bindings.enumerated() {
      let index = offset + 1
      switch binding {
      case .blob(let bytes):
        try statement.bind(.blob(Data(bytes)), at: index)
      case .bool(let bool):
        try statement.bind(.integer(bool ? 1 : 0), at: index)
      case .date(let date):
        try statement.bind(.text(TursoDateFormatting.string(from: date)), at: index)
      case .double(let double):
        try statement.bind(.double(double), at: index)
      case .int(let int):
        try statement.bind(.integer(int), at: index)
      case .null:
        try statement.bind(.null, at: index)
      case .text(let text):
        try statement.bind(.text(text), at: index)
      case .uint(let uint) where uint <= UInt64(Int64.max):
        try statement.bind(.integer(Int64(uint)), at: index)
      case .uint(let uint):
        throw TursoError(code: -1, message: "UInt64 overflow binding \(uint)")
      case .uuid(let uuid):
        try statement.bind(.text(uuid.uuidString.lowercased()), at: index)
      case .invalid(let error):
        throw error.underlyingError
      }
    }
  }
}
