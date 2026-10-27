import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        URLMacro.self,
        SelectorMacro.self,
        KeychainMacro.self,
        UserDefaultMacro.self,
        StoragePublisherProjectionMacro.self,
        ObjectiveCBridgeableMacro.self,
    ]
}
