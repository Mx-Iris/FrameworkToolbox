import MacroToolbox
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// The two implementations behind `_EquatableMemberCheck` and
// `_HashableMemberCheck`. Which one runs is the compiler's decision, made by
// overload resolution on the member's type — see the macro declarations. The
// macros are attached to the member itself, so `declaration` is the property
// the caller wrote and a diagnostic placed on it lands in the caller's code.

/// The member's type conforms. Nothing to generate and nothing to report.
public enum ComparableMemberMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// The member's type does not conform: report it on the member, with a fix
/// that leaves the member out.
public enum UncomparableMemberMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let propertyName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        else {
            return []
        }

        let requiredProtocol = node.unqualifiedName == "_HashableMemberCheck" ? "Hashable" : "Equatable"
        let writtenType = binding.typeAnnotation?.type.trimmedDescription

        // On the type when there is one: that is what has to change.
        context.diagnose(
            Diagnostic(
                node: binding.typeAnnotation.map { Syntax($0.type) } ?? Syntax(binding.pattern),
                message: UncomparableMemberDiagnostic(
                    propertyName: propertyName,
                    writtenType: writtenType,
                    requiredProtocol: requiredProtocol
                ),
                fixIt: .replace(
                    message: IgnoreMemberFixIt(propertyName: propertyName),
                    oldNode: varDecl,
                    newNode: ignoring(varDecl)
                )
            )
        )
        return []
    }

    /// The declaration with `@EquatableIgnored` added after its own attributes.
    ///
    /// The check attributes are dropped first. The compiler hands this macro
    /// the declaration as the caller wrote it, but the test harness includes
    /// the attributes `@Equatable` added, and a fix built from those would
    /// paste them into the caller's source.
    private static func ignoring(_ varDecl: VariableDeclSyntax) -> VariableDeclSyntax {
        // The indentation belongs to whichever token comes first, which the new
        // attribute can become: take it off before adding, put it back after.
        let leadingTrivia = varDecl.leadingTrivia
        let detached = varDecl.with(\.leadingTrivia, [])

        let ownAttributes = detached.attributes.filter { element in
            guard case .attribute(let attribute) = element else { return true }
            return attribute.unqualifiedName != "_EquatableMemberCheck"
                && attribute.unqualifiedName != "_HashableMemberCheck"
        }

        // Spaced to sit where it lands: after an attribute that ends without
        // one it needs a space in front, and before a `var` on the next line it
        // must not leave one at the end of its own.
        let previousAttributeEndsWithSpace = ownAttributes.last?.trailingTrivia.contains { piece in
            piece.isWhitespace && !piece.isNewline
        } ?? true
        let followingToken = detached.modifiers.first?.name ?? detached.bindingSpecifier
        let followingTokenStartsLine = followingToken.leadingTrivia.contains { $0.isNewline }
        let ignoredAttribute = AttributeSyntax(
            leadingTrivia: previousAttributeEndsWithSpace ? [] : .space,
            attributeName: IdentifierTypeSyntax(name: .identifier("EquatableIgnored")),
            trailingTrivia: followingTokenStartsLine ? [] : .space
        )

        return detached
            .with(\.attributes, ownAttributes + [.attribute(ignoredAttribute)])
            .with(\.leadingTrivia, leadingTrivia)
    }
}

struct UncomparableMemberDiagnostic: DiagnosticMessage {
    let propertyName: String
    /// The type as the caller wrote it, or `nil` when the property has no
    /// annotation and the type was inferred from its initial value.
    let writtenType: String?
    let requiredProtocol: String

    var message: String {
        let subject = writtenType.map { "'\($0)'" } ?? "the type of '\(propertyName)'"
        let member = writtenType == nil ? "it" : "'\(propertyName)'"
        if requiredProtocol == "Hashable" {
            return """
            \(subject) does not conform to 'Hashable', so the 'hash(into:)' that '@Equatable' \
            writes for a Hashable type cannot include \(member)
            """
        }
        return "\(subject) does not conform to 'Equatable', so '@Equatable' cannot compare \(member)"
    }

    var diagnosticID: MessageID {
        MessageID(domain: "EquatableMacro", id: "uncomparableMember")
    }

    var severity: DiagnosticSeverity { .error }
}

struct IgnoreMemberFixIt: FixItMessage {
    let propertyName: String

    var message: String {
        "Apply '@EquatableIgnored' to leave '\(propertyName)' out of the comparison"
    }

    var fixItID: MessageID {
        MessageID(domain: "EquatableMacro", id: "ignoreMember")
    }
}
