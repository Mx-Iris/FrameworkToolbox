import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DyldInterposeMacro.self,
        DyldDynamicInterposeMacro.self,
    ]
}
