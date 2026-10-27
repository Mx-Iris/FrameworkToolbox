import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Source: https://github.com/ordo-one/equatable
/// 
/// A peer macro that marks properties to be ignored in `Equatable` conformance generation.
///
/// This macro allows developers to explicitly exclude specific properties from the equality comparison
/// when using the `@Equatable` macro. It performs validation to ensure it's used correctly.
///
/// Usage:
/// ```swift
/// @Equatable
/// struct User {
///     let id: UUID
///     let name: String
///     @EquatableIgnored var temporaryCache: [String: Any] // This property will be excluded
/// }
/// ```
///
/// This macro cannot be applied to:
/// - Non-property declarations
/// - Closure properties
/// - Properties already marked with `@Binding`
public struct EquatableIgnoredMacro: PeerMacro {
    private static let unignorablePropertyWrappers: Set = [
        "Binding",
        "FocusedBinding"
    ]

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first
        else {
            let diagnostic = Diagnostic(
                node: node,
                message: MacroExpansionErrorMessage("@EquatableIgnored can only be applied to properties")
            )
            context.diagnose(diagnostic)
            return []
        }

        if let typeAnnotation = binding.typeAnnotation?.type {
            if isClosure(type: typeAnnotation) {
                let diagnostic = Diagnostic(
                    node: node,
                    message: MacroExpansionErrorMessage("@EquatableIgnored cannot be applied to closures")
                )
                context.diagnose(diagnostic)
            }
        }

        if let unignorableAttribute = varDecl.attributes
           .compactMap(attributeName(_:))
           .first(where: unignorablePropertyWrappers.contains(_:)) {
            let diagnostic = Diagnostic(
                node: node,
                message: MacroExpansionErrorMessage("@EquatableIgnored cannot be applied to @\(unignorableAttribute) properties")
            )
            context.diagnose(diagnostic)
            return []
        }

        return []
    }

    private static func attributeName(_ attribute: AttributeListSyntax.Element) -> String? {
        guard let attributeName = attribute.as(AttributeSyntax.self)?.attributeName else {
            return nil
        }
        if let identifier = attributeName.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        // `@SwiftUI.Binding` is the same wrapper; another module's `Binding` is not.
        if let member = attributeName.as(MemberTypeSyntax.self),
           member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "SwiftUI" {
            return member.name.text
        }
        return nil
    }
}
