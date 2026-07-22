import SwiftSyntax
import SwiftSyntaxMacros

/// Generates Turso `CREATE MATERIALIZED VIEW` DDL (IVM).
public struct MaterializedViewMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw BoutiqueMacroError.message("@MaterializedView can only be applied to a struct")
    }

    let args = AttributeArgs(node)
    let viewName = args.string("name") ?? BoutiqueSQL.defaultTableName(from: structDecl.name.text)
    guard let source = args.string("as"), !source.isEmpty else {
      throw BoutiqueMacroError.message(
        "@MaterializedView requires a source SQL string, e.g. @MaterializedView(as: \"SELECT ...\")"
      )
    }

    let lower = source.lowercased()
    if lower.contains("materialized view") {
      throw BoutiqueMacroError.message(
        "Nested MATERIALIZED VIEW references are not supported in @MaterializedView source SQL"
      )
    }
    if lower.contains("temporary") {
      throw BoutiqueMacroError.message("TEMPORARY is not supported in materialized view sources")
    }
    if lower.contains("without rowid") {
      throw BoutiqueMacroError.message(
        "WITHOUT ROWID is not supported in materialized view sources"
      )
    }

    let ddl =
      "CREATE MATERIALIZED VIEW IF NOT EXISTS \(BoutiqueSQL.quoteIdent(viewName)) AS \(source)"
    let literal = ddl.swiftStringLiteral

    return [
      """
      public static var boutiqueTableName: String { \(literal: viewName) }

      public static var boutiqueCreateStatements: [String] { [\(raw: literal)] }
      """
    ]
  }
}

extension MaterializedViewMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let ext: DeclSyntax = """
      extension \(type.trimmed): BoutiqueSchema {}
      """
    return [ext.as(ExtensionDeclSyntax.self)].compactMap { $0 }
  }
}
