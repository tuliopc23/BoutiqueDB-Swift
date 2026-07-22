import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates `BoutiqueSchema` table DDL for Turso-specific table options.
public struct BoutiqueTableMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw BoutiqueMacroError.message("@BoutiqueTable can only be applied to a struct")
    }

    let typeName = structDecl.name.text
    let args = AttributeArgs(node)
    let tableName = args.string("name") ?? BoutiqueSQL.defaultTableName(from: typeName)
    let withoutRowid = args.bool("withoutRowid") ?? false
    let strict = args.bool("strict") ?? false

    let columns = try parseColumns(from: structDecl)
    guard !columns.isEmpty else {
      throw BoutiqueMacroError.message("@BoutiqueTable requires at least one stored property")
    }

    var columnSQL: [String] = []
    for col in columns {
      var line = "  \(BoutiqueSQL.quoteIdent(col.name)) \(col.sqlType)"
      if col.isPrimaryKey {
        line += " PRIMARY KEY"
      }
      if !col.isOptional && !col.isPrimaryKey {
        line += " NOT NULL"
      } else if !col.isOptional && col.isPrimaryKey {
        line += " NOT NULL"
      }
      if let expr = col.generatedExpression {
        line += " GENERATED ALWAYS AS (\(expr)) VIRTUAL"
      }
      columnSQL.append(line)
    }

    var ddl = "CREATE TABLE IF NOT EXISTS \(BoutiqueSQL.quoteIdent(tableName)) (\n"
    ddl += columnSQL.joined(separator: ",\n")
    ddl += "\n)"
    if withoutRowid { ddl += " WITHOUT ROWID" }
    if strict { ddl += " STRICT" }

    let ftsAttrs = structDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }
      .filter { $0.attributeName.trimmedDescription == "FTSIndex" }
    let vectorAttrs = structDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }
      .filter { $0.attributeName.trimmedDescription == "VectorIndex" }

    var extraStatements: [String] = []
    for attr in ftsAttrs {
      extraStatements.append(try FTSIndexMacro.buildDDL(attribute: attr, tableName: tableName))
    }
    for attr in vectorAttrs {
      extraStatements.append(try VectorIndexMacro.buildDDL(attribute: attr, tableName: tableName))
    }

    let statementsLiteral = ([ddl] + extraStatements)
      .map(\.swiftStringLiteral)
      .joined(separator: ",\n      ")
    let columnsLiteral = columns.map { column in
      let defaultSQL = "nil"
      let generated = column.generatedExpression.map { $0.swiftStringLiteral } ?? "nil"
      return
        "BoutiqueColumnSpec(name: \(column.name.swiftStringLiteral), sqlType: \(column.sqlType.swiftStringLiteral), defaultSQL: \(defaultSQL), isNullable: \(column.isOptional), isPrimaryKey: \(column.isPrimaryKey), generatedExpression: \(generated))"
    }.joined(separator: ",\n      ")

    let decl: DeclSyntax = """
      public static var boutiqueTableName: String { \(literal: tableName) }

      public static var boutiqueCreateStatements: [String] {
        [
          \(raw: statementsLiteral)
        ]
      }

      public static var boutiqueColumns: [BoutiqueColumnSpec] {
        [
          \(raw: columnsLiteral)
        ]
      }
      """
    return [decl]
  }

  private static func parseColumns(from structDecl: StructDeclSyntax) throws -> [ParsedColumn] {
    var columns: [ParsedColumn] = []
    for member in structDecl.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self),
        varDecl.bindings.count == 1,
        let binding = varDecl.bindings.first,
        let ident = binding.pattern.as(IdentifierPatternSyntax.self),
        let typeAnnotation = binding.typeAnnotation?.type
      else { continue }

      // Skip computed properties
      if binding.accessorBlock != nil { continue }

      let name = ident.identifier.text
      let isPK =
        varDecl.attributes.contains { attr in
          guard let a = attr.as(AttributeSyntax.self) else { return false }
          return a.attributeName.trimmedDescription == "Column"
            && AttributeArgs(a).boolishPrimaryKey
        } || name == "id"

      let generated = varDecl.attributes
        .compactMap { $0.as(AttributeSyntax.self) }
        .first { $0.attributeName.trimmedDescription == "GeneratedColumn" }
        .flatMap { AttributeArgs($0).string("expression") }

      columns.append(
        ParsedColumn(
          name: name,
          sqlType: try BoutiqueSQL.sqlType(for: typeAnnotation),
          isOptional: BoutiqueSQL.isOptional(typeAnnotation),
          isPrimaryKey: isPK,
          generatedExpression: generated
        )
      )
    }
    return columns
  }
}

extension BoutiqueTableMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let ext: DeclSyntax = """
      extension \(type.trimmed): BoutiqueSchemaColumns {}
      """
    guard let extensionDecl = ext.as(ExtensionDeclSyntax.self) else { return [] }
    return [extensionDecl]
  }
}

// MARK: - Helpers

struct AttributeArgs {
  private let arguments: LabeledExprListSyntax?

  init(_ attribute: AttributeSyntax) {
    if case .argumentList(let list) = attribute.arguments {
      self.arguments = list
    } else {
      self.arguments = nil
    }
  }

  func string(_ label: String) -> String? {
    guard let arguments else { return nil }
    for arg in arguments {
      guard arg.label?.text == label,
        let lit = arg.expression.as(StringLiteralExprSyntax.self)
      else { continue }
      return lit.representedLiteralValue
    }
    return nil
  }

  func bool(_ label: String) -> Bool? {
    guard let arguments else { return nil }
    for arg in arguments {
      if arg.label?.text == label {
        let text = arg.expression.trimmedDescription
        if text == "true" { return true }
        if text == "false" { return false }
      }
    }
    return nil
  }

  var boolishPrimaryKey: Bool {
    guard let arguments else { return false }
    for arg in arguments {
      if arg.label?.text == "primaryKey" {
        let text = arg.expression.trimmedDescription
        return text == "true" || text.hasPrefix(".")
      }
    }
    return false
  }

  func unlabeledStrings() -> [String] {
    guard let arguments else { return [] }
    return arguments.compactMap { arg in
      guard arg.label == nil,
        let lit = arg.expression.as(StringLiteralExprSyntax.self)
      else { return nil }
      return lit.representedLiteralValue
    }
  }

  func enumCase(_ label: String) -> String? {
    guard let arguments else { return nil }
    for arg in arguments {
      if arg.label?.text == label {
        let text = arg.expression.trimmedDescription
        if text.hasPrefix(".") {
          return String(text.dropFirst())
        }
        if let member = arg.expression.as(MemberAccessExprSyntax.self) {
          return member.declName.baseName.text
        }
      }
    }
    return nil
  }
}

enum BoutiqueMacroError: Error, CustomStringConvertible {
  case message(String)
  var description: String {
    switch self {
    case .message(let s): return s
    }
  }
}

extension String {
  /// Encode as a Swift double-quoted string literal for macro expansion.
  var swiftStringLiteral: String {
    var out = "\""
    for ch in self {
      switch ch {
      case "\\": out += "\\\\"
      case "\"": out += "\\\""
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default: out.append(ch)
      }
    }
    out += "\""
    return out
  }
}
