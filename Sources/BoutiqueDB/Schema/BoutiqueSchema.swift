import Foundation

/// Types that can emit Turso DDL for `BoutiqueDB.create`.
///
/// Macros (`@BoutiqueTable`, `@FTSIndex`, `@VectorIndex`, `@MaterializedView`)
/// generate conformances so Apple apps never hand-write Turso-specific SQL.
public protocol BoutiqueSchema: Sendable {
  /// Preferred table / view name.
  static var boutiqueTableName: String { get }

  /// Ordered DDL statements to apply (CREATE TABLE / INDEX / MATERIALIZED VIEW).
  static var boutiqueCreateStatements: [String] { get }
}

/// Optional additive column metadata for ``BoutiqueDB/syncSchema(_:policy:)``.
public protocol BoutiqueSchemaColumns: BoutiqueSchema {
  /// Columns to ensure exist (`ALTER TABLE … ADD COLUMN` when missing).
  static var boutiqueColumns: [BoutiqueColumnSpec] { get }
}

/// A single additive column description for schema sync / migrations.
public struct BoutiqueColumnSpec: Sendable, Equatable {
  public var name: String
  public var sqlType: String
  public var defaultSQL: String?
  public var isNullable: Bool
  public var isPrimaryKey: Bool
  public var generatedExpression: String?

  public init(
    name: String,
    sqlType: String,
    defaultSQL: String? = nil,
    isNullable: Bool = true,
    isPrimaryKey: Bool = false,
    generatedExpression: String? = nil
  ) {
    self.name = name
    self.sqlType = sqlType
    self.defaultSQL = defaultSQL
    self.isNullable = isNullable
    self.isPrimaryKey = isPrimaryKey
    self.generatedExpression = generatedExpression
  }
}

extension BoutiqueSchema {
  public static var boutiqueTableName: String {
    let name = String(describing: Self.self)
    let lowered = name.prefix(1).lowercased() + name.dropFirst()
    if lowered.hasSuffix("s") { return String(lowered) }
    if lowered.hasSuffix("y") { return String(lowered.dropLast()) + "ies" }
    return String(lowered) + "s"
  }

  public static var boutiqueCreateStatements: [String] { [] }
}

// MARK: - Manual descriptors (Turso-advantage builders without macros)

/// Full-text index descriptor for Turso Tantivy FTS.
public struct FTSIndexDescriptor: Sendable, Equatable {
  public var name: String
  public var table: String
  public var columns: [String]
  public var tokenizer: FTSTokenizer

  public init(
    name: String? = nil,
    table: String,
    columns: [String],
    tokenizer: FTSTokenizer = .default
  ) {
    self.table = table
    self.columns = columns
    self.tokenizer = tokenizer
    self.name = name ?? "\(table)_\(columns.joined(separator: "_"))_fts"
  }

  public var ddl: String {
    let cols = columns.map { quoteIdent($0) }.joined(separator: ", ")
    return
      "CREATE INDEX IF NOT EXISTS \(quoteIdent(name)) ON \(quoteIdent(table)) USING fts(\(cols)) WITH (tokenizer = '\(tokenizer.rawValue)')"
  }
}

public enum FTSTokenizer: String, Sendable, Equatable, CaseIterable {
  case `default`
  case raw
  case simple
  case whitespace
  case ngram
}

/// Vector index descriptor for Turso vector search.
public struct VectorIndexDescriptor: Sendable, Equatable {
  public var name: String
  public var table: String
  public var column: String
  public var metric: VectorMetric

  public init(
    name: String? = nil,
    table: String,
    column: String,
    metric: VectorMetric = .cosine
  ) {
    self.table = table
    self.column = column
    self.metric = metric
    self.name = name ?? "\(table)_\(column)_vector"
  }

  public var ddl: String {
    "CREATE INDEX IF NOT EXISTS \(quoteIdent(name)) ON \(quoteIdent(table)) USING vector(\(quoteIdent(column))) WITH (metric = '\(metric.rawValue)')"
  }
}

public enum VectorMetric: String, Sendable, Equatable, CaseIterable {
  case cosine
  case l2
  case dot
  case jaccard
}

/// Materialized view (IVM) descriptor.
public struct MaterializedViewDescriptor: Sendable, Equatable {
  public var name: String
  public var sourceSQL: String

  public init(name: String, sourceSQL: String) {
    self.name = name
    self.sourceSQL = sourceSQL
  }

  public var ddl: String {
    "CREATE MATERIALIZED VIEW IF NOT EXISTS \(quoteIdent(name)) AS \(sourceSQL)"
  }
}

/// Table options that go beyond stock SQLite defaults.
public struct BoutiqueTableDescriptor: Sendable, Equatable {
  public var name: String
  public var columnsSQL: String
  public var withoutRowid: Bool
  public var strict: Bool

  public init(
    name: String,
    columnsSQL: String,
    withoutRowid: Bool = false,
    strict: Bool = false
  ) {
    self.name = name
    self.columnsSQL = columnsSQL
    self.withoutRowid = withoutRowid
    self.strict = strict
  }

  public var ddl: String {
    var sql = "CREATE TABLE IF NOT EXISTS \(quoteIdent(name)) (\n\(columnsSQL)\n)"
    if withoutRowid { sql += " WITHOUT ROWID" }
    if strict { sql += " STRICT" }
    return sql
  }
}

func quoteIdent(_ name: String) -> String {
  "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
}
