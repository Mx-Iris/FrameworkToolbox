import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DynamicSubclassHookMacro.self,
        DynamicSubclassMethodBodyMacro.self,
    ]
}
