import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MutexMacro.self,
        EquatableMacro.self,
        EquatableIgnoredMacro.self,
        EquatableIgnoredUnsafeClosureMacro.self,
        AssociatedValueMacro.self,
        CaseCheckableMacro.self,
        AvailableNonMutatingMacro.self,
        AvailableMutatingMacro.self,
        DyldInterposeMacro.self,
        AddAsyncMacro.self,
        AddAsyncAllMembersMacro.self,
        AddCompletionHandlerMacro.self,
    ]
}
