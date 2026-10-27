import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// `_HookContainerIsolationCheck`: which of the two implementations runs is the
// compiler's decision, made by overload resolution on the container
// initializer's function type — see the macro declarations.

/// The container is not isolated. Nothing to generate.
public enum NonisolatedHookContainerMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// The container is isolated to the main actor: report it. The generating
/// macro maps this call to its own attribute with `#sourceLocation`, so the
/// error lands on the line that declares the hook.
public enum MainActorHookContainerMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let initializer = node.arguments.first?.expression
        let containerName = initializer?.as(MemberAccessExprSyntax.self)?.base?.trimmedDescription ?? "The hook container"
        context.emit(
            .error(
                "hookContainerIsolatedToMainActor",
                """
                '\(containerName)' is isolated to the main actor, but the Objective-C runtime calls its \
                replacements synchronously on whichever thread invokes the hooked method. Mark it \
                'nonisolated' — in a module whose default isolation is 'MainActor', every type is \
                main-actor isolated unless it says otherwise.
                """
            ),
            at: node
        )
        return []
    }
}

/// The statements that put the container's isolation to the compiler, for a
/// generated function body. Mapped to `attribute`'s line so that the report
/// lands on the line declaring the hook; see `_HookContainerIsolationCheck`.
///
/// - Parameter initializerReference: The container's initializer as a function
///   value, e.g. `Hooks.init(host:originalImplementation:)`.
func hookContainerIsolationCheck(
    initializerReference: String,
    attribute: AttributeSyntax,
    in context: some MacroExpansionContext
) -> String {
    let check = "#_HookContainerIsolationCheck(initializer: \(initializerReference))"
    guard let location = context.location(of: attribute, at: .afterLeadingTrivia, filePathMode: .filePath) else {
        return check
    }
    return """
    #sourceLocation(file: \(location.file), line: \(location.line))
    \(check)
    #sourceLocation()
    """
}
