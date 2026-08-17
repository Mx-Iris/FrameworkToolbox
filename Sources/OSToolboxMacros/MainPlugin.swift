import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MutexMacro.self,
        OSAllocatedUnfairLockMacro.self,
        LoggableMacro.self,
        LogMacro.self,
        SignpostableMacro.self,
        SignpostMacro.self,
        SignpostIntervalMacro.self,
    ]
}
