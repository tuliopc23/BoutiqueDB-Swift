import SwiftSyntax
import SwiftSyntaxMacros

/// Marker / contributor macro for Turso FTS indexes (`CREATE INDEX ... USING fts`).
///
/// When applied with `@BoutiqueTable`, the table macro incorporates the FTS DDL.
/// When applied alone to a struct, generates `boutiqueFTSCreateStatements`.
public struct FTSIndexMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // If BoutiqueTable is also present, it owns createStatements — only emit FTS helper.
    let hasBoutiqueTable = declaration.attributes.contains {
      $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "BoutiqueTable"
    }

    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw BoutiqueMacroError.message("@FTSIndex can only be applied to a struct")
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
        public static var boutiqueFTSCreateStatements: [String] { [\(raw: literal)] }
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
    var columns = args.unlabeledStrings()
    if columns.isEmpty {
      // Support columns: ["title", "body"] labeled form via array literal
      if case .argumentList(let list) = attribute.arguments {
        for arg in list where arg.label?.text == "columns" {
          if let array = arg.expression.as(ArrayExprSyntax.self) {
            columns = array.elements.compactMap {
              $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
            }
          }
        }
      }
    }
    guard !columns.isEmpty else {
      throw BoutiqueMacroError.message(
        "@FTSIndex requires one or more column names, e.g. @FTSIndex(\"title\", \"body\")"
      )
    }

    let tokenizer = args.enumCase("tokenizer") ?? "default"
    let allowed = ["default", "raw", "simple", "whitespace", "ngram"]
    guard allowed.contains(tokenizer) else {
      throw BoutiqueMacroError.message(
        "Unsupported FTS tokenizer '.\(tokenizer)'. Allowed: \(allowed.map { ".\($0)" }.joined(separator: ", "))"
      )
    }

    let indexName =
      args.string("name")
      ?? "\(tableName)_\(columns.joined(separator: "_"))_fts"

    let colList = columns.map { BoutiqueSQL.quoteIdent($0) }.joined(separator: ", ")
    // Turso Tantivy FTS
    return
      "CREATE INDEX IF NOT EXISTS \(BoutiqueSQL.quoteIdent(indexName)) ON \(BoutiqueSQL.quoteIdent(tableName)) USING fts(\(colList)) WITH (tokenizer = '\(tokenizer)')"
  }
}

extension FTSIndexMacro: ExtensionMacro {
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
