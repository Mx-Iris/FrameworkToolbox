import Foundation
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct FrameworkToolboxMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        FrameworkToolboxCompatibleMacro.self,
    ]
}
