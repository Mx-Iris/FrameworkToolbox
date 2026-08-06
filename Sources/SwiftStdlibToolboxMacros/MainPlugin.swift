import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        EquatableMacro.self,
        EquatableIgnoredMacro.self,
        EquatableIgnoredUnsafeClosureMacro.self,
        AssociatedValueMacro.self,
        CaseCheckableMacro.self,
        AvailableNonMutatingMacro.self,
        AvailableMutatingMacro.self,
        DyldInterposeMacro.self,
        DyldDynamicInterposeMacro.self,
        AddAsyncMacro.self,
        AddAsyncAllMembersMacro.self,
        AddCompletionHandlerMacro.self,
    ]
}
