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
        AddAsyncMacro.self,
        AddAsyncAllMembersMacro.self,
        AddCompletionHandlerMacro.self,
        BijectionMacro.self,
        CaseTagMacro.self,
        MirroredCasesMacro.self,
        DefaultedCasesMacro.self,
        ProjectionMacro.self,
        ProjectionFunctionMacro.self,
    ]
}
