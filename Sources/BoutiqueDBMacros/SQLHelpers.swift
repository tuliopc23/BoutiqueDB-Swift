import Foundation
import SwiftSyntax

enum BoutiqueSQL {
  static func quoteIdent(_ name: String) -> String {
    "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
  }

  static func defaultTableName(from typeName: String) -> String {
    // Match StructuredQueries-style pluralization lightly: Note -> notes
    let lowered = typeName.prefix(1).lowercased() + typeName.dropFirst()
    if lowered.hasSuffix("s") { return String(lowered) }
    if lowered.hasSuffix("y") {
      return String(lowered.dropLast()) + "ies"
    }
    return String(lowered) + "s"
  }

  static func sqlType(for typeSyntax: TypeSyntax) -> String {
    let text = typeSyntax.trimmedDescription
      .replacingOccurrences(of: "?", with: "")
      .replacingOccurrences(of: " ", with: "")
    switch text {
    case "Int", "Int64", "Int32", "UInt", "UInt64", "UInt32", "Bool":
      return "INTEGER"
    case "Double", "Float", "CGFloat":
      return "REAL"
    case "Data":
      return "BLOB"
    case "Vector32", "Vector32Sparse":
      return "BLOB"
    default:
      return "TEXT"
    }
  }

  static func isOptional(_ typeSyntax: TypeSyntax) -> Bool {
    if typeSyntax.is(OptionalTypeSyntax.self) { return true }
    if typeSyntax.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return true }
    let text = typeSyntax.trimmedDescription
    return text.hasSuffix("?") || text.hasPrefix("Optional<")
  }
}

struct ParsedColumn {
  var name: String
  var sqlType: String
  var isOptional: Bool
  var isPrimaryKey: Bool
  var generatedExpression: String?
}
