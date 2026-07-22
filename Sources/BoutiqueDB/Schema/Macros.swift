/// Declares a Turso-aware table schema (STRICT / WITHOUT ROWID / generated columns)
/// and optional stacked `@FTSIndex` / `@VectorIndex` attributes.
///
/// ```swift
/// @BoutiqueTable(strict: true)
/// @FTSIndex("title", "body")
/// struct Note {
///   @Column(primaryKey: true) let id: String
///   var title: String
///   var body: String
/// }
/// ```
@attached(
  member,
  names: named(boutiqueTableName), named(boutiqueCreateStatements), named(boutiqueColumns)
)
@attached(extension, conformances: BoutiqueSchema, BoutiqueSchemaColumns)
public macro BoutiqueTable(
  name: String? = nil,
  withoutRowid: Bool = false,
  strict: Bool = false
) = #externalMacro(module: "BoutiqueDBMacros", type: "BoutiqueTableMacro")

/// Declares a Turso Tantivy full-text index (`CREATE INDEX ... USING fts`).
@attached(member, names: named(boutiqueCreateStatements), named(boutiqueFTSCreateStatements))
@attached(extension, conformances: BoutiqueSchema)
public macro FTSIndex(
  _ columns: String...,
  tokenizer: FTSTokenizer = .default,
  name: String? = nil
) = #externalMacro(module: "BoutiqueDBMacros", type: "FTSIndexMacro")

/// Declares a Turso vector index (`CREATE INDEX ... USING vector`).
@attached(member, names: named(boutiqueCreateStatements), named(boutiqueVectorCreateStatements))
@attached(extension, conformances: BoutiqueSchema)
public macro VectorIndex(
  _ column: String,
  metric: VectorMetric = .cosine,
  name: String? = nil
) = #externalMacro(module: "BoutiqueDBMacros", type: "VectorIndexMacro")

/// Declares a Turso materialized view (incremental view maintenance).
@attached(member, names: named(boutiqueTableName), named(boutiqueCreateStatements))
@attached(extension, conformances: BoutiqueSchema)
public macro MaterializedView(
  name: String? = nil,
  as sourceSQL: String
) = #externalMacro(module: "BoutiqueDBMacros", type: "MaterializedViewMacro")
