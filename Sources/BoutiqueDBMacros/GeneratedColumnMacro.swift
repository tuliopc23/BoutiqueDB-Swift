import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for generated columns (`GENERATED ALWAYS AS (...)`).
///
/// `@BoutiqueTable` reads this attribute during expansion; this macro itself
/// does not emit extra declarations.
public struct GeneratedColumnMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    []
  }
}
