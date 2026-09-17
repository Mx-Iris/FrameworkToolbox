import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        URLMacro.self,
        SelectorMacro.self,
        KeychainMacro.self,
        UserDefaultMacro.self,
        ObjectiveCBridgeableMacro.self,
    ]
}
