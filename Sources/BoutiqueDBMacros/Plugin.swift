import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct BoutiqueDBMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    BoutiqueTableMacro.self,
    GeneratedColumnMacro.self,
    FTSIndexMacro.self,
    VectorIndexMacro.self,
    MaterializedViewMacro.self,
  ]
}
