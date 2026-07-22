import SwiftSyntax
import SwiftSyntaxMacros

/// Marker / contributor macro for Turso vector indexes (`CREATE INDEX ... USING vector`).
public struct VectorIndexMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    let hasBoutiqueTable = declaration.attributes.contains {
      $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "BoutiqueTable"
    }

    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw BoutiqueMacroError.message("@VectorIndex can only be applied to a struct")
    }
    let boutiqueAttr = declaration.attributes
      .compactMap { $0.as(AttributeSyntax.self) }
      .first { $0.attributeName.trimmedDescription == "BoutiqueTable" }
    let tableName =
      boutiqueAttr.flatMap { AttributeArgs($0).string("name") }
      ?? BoutiqueSQL.defaultTableName(from: structDecl.name.text)

    let ddl = try buildDDL(attribute: node, tableName: tableName)
    let literal = ddl.swiftStringLiteral

    if hasBoutiqueTable {
      return [
        """
        public static var boutiqueVectorCreateStatements: [String] { [\(raw: literal)] }
        """
      ]
    }
    return [
      """
      public static var boutiqueCreateStatements: [String] { [\(raw: literal)] }
      """
    ]
  }

  static func buildDDL(attribute: AttributeSyntax, tableName: String) throws -> String {
    let args = AttributeArgs(attribute)
    var column = args.unlabeledStrings().first
    if column == nil {
      if case .argumentList(let list) = attribute.arguments {
        for arg in list where arg.label?.text == "column" {
          column = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        }
      }
    }
    guard let column else {
      throw BoutiqueMacroError.message(
        "@VectorIndex requires a column name, e.g. @VectorIndex(\"embedding\", metric: .cosine)"
      )
    }

    let metric = args.enumCase("metric") ?? "cosine"
    let allowed = ["cosine", "l2", "dot", "jaccard"]
    guard allowed.contains(metric) else {
      throw BoutiqueMacroError.message(
        "Unsupported vector metric '.\(metric)'. Allowed: \(allowed.map { ".\($0)" }.joined(separator: ", "))"
      )
    }

    let indexName = args.string("name") ?? "\(tableName)_\(column)_vector"
    return
      "CREATE INDEX IF NOT EXISTS \(BoutiqueSQL.quoteIdent(indexName)) ON \(BoutiqueSQL.quoteIdent(tableName)) USING vector(\(BoutiqueSQL.quoteIdent(column))) WITH (metric = '\(metric)')"
  }
}

extension VectorIndexMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let hasBoutiqueTable = declaration.attributes.contains {
      $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "BoutiqueTable"
    }
    if hasBoutiqueTable { return [] }
    let ext: DeclSyntax = """
      extension \(type.trimmed): BoutiqueSchema {}
      """
    return [ext.as(ExtensionDeclSyntax.self)].compactMap { $0 }
  }
}
