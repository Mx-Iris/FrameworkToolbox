import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder
import SwiftDiagnostics

public enum FrameworkToolboxCompatibleMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let arguments = try parseArguments(from: node, in: context)
        let accessLevel = arguments.accessLevel ?? "public"
        // The instance `box` setter has to write back, or every `mutating` method
        // reached through `.box` is silently a no-op: the getter hands out a fresh
        // `FrameworkToolbox` value, the method mutates that temporary, and an empty
        // setter drops it. Nothing fails to compile and no warning is emitted.
        //
        // Under reference semantics that write-back is both impossible and
        // unnecessary. A setter in a class-bound protocol's extension is not
        // `mutating`, so `self` cannot be assigned — and the compiler does not
        // diagnose it, it crashes in SILGen (signal 5, `While silgen emitFunction
        // … for setter for box`). Unnecessary because the box wraps the same
        // object, so mutating through it is already visible everywhere.
        //
        // Which case applies depends on the protocol's declaration, which this
        // macro never sees: it is attached to `extension Collection {}`, not to
        // `Collection`. So the accessors come from `_FrameworkToolboxBoxAccessors`,
        // whose overloads let the compiler decide from `Self: AnyObject`.
        return [
            """
            \(raw: accessLevel) static var box: FrameworkToolbox<Self>.Type {
                set {}
                get { FrameworkToolbox<Self>.self }
            }
            """,
            """
            @_FrameworkToolboxBoxAccessors(Self.self)
            \(raw: accessLevel) var box: FrameworkToolbox<Self>
            """,
            """
            \(raw: accessLevel) subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                set { box[keyPath: keyPath] = newValue }
                get { box[keyPath: keyPath] }
            }
            """,
            """
            \(raw: accessLevel) subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                set { box[keyPath: keyPath] = newValue }
                get { box[keyPath: keyPath] }
            }
            """,
            """
            \(raw: accessLevel) subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                box[keyPath: keyPath]
            }
            """,
            """
            \(raw: accessLevel) static subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                set { box[keyPath: keyPath] = newValue }
                get { box[keyPath: keyPath] }
            }
            """,
            """
            \(raw: accessLevel) static subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                set { box[keyPath: keyPath] = newValue }
                get { box[keyPath: keyPath] }
            }
            """,
            """
            \(raw: accessLevel) static subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                box[keyPath: keyPath]
            }
            """,
        ]
    }
    
    
    /// The arguments `@FrameworkToolboxExtension` was written with.
    struct Arguments {
        /// The access level to emit the generated members at; `nil` means the
        /// default, `public`.
        var accessLevel: String?
    }

    /// Parses arguments from the attribute syntax.
    ///
    /// The deprecated `referenceSemantics:` is accepted and ignored: the setter
    /// is now chosen by the compiler, and an argument that disagreed with the
    /// protocol would only have reintroduced the problem it once worked around.
    private static func parseArguments(
        from node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) throws -> Arguments {
        var arguments = Arguments()

        guard let argumentList = node.arguments?.as(LabeledExprListSyntax.self) else {
            return arguments
        }

        for argument in argumentList where argument.label == nil {
            // The only unlabelled argument is the access level, written as a
            // member access such as `.public`.
            guard let memberAccessExpression = argument.expression.as(MemberAccessExprSyntax.self) else {
                throw MacroError.invalidAccessLevelArgument(node: argument.expression)
            }
            arguments.accessLevel = memberAccessExpression.declName.baseName.text
        }

        return arguments
    }
}

// MARK: - The instance `box` accessors

/// `_FrameworkToolboxBoxAccessors` for a `Self` that may be a value type: the
/// setter writes back, so `mutating` methods reached through `.box` take effect.
public enum ValueSemanticsBoxAccessorsMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        [
            "set { self = newValue.base }",
            "get { FrameworkToolbox(self) }",
        ]
    }
}

/// `_FrameworkToolboxBoxAccessors` for a `Self` constrained to `AnyObject`: the
/// setter stays empty, since it is not `mutating` and the box wraps the same
/// object anyway.
public enum ReferenceSemanticsBoxAccessorsMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        [
            "set {}",
            "get { FrameworkToolbox(self) }",
        ]
    }
}

/// Helper to provide diagnostic messages.
private enum MacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case invalidAccessLevelArgument(node: ExprSyntax)

    var description: String {
        switch self {
        case .invalidAccessLevelArgument:
            return "Invalid argument for access level. Please use a member of the `AccessLevel` enum, like `.public`."
        }
    }
    
    var message: String { description }
    
    var diagnosticID: MessageID {
        MessageID(domain: "\(FrameworkToolboxCompatibleMacro.self)", id: "\(Self.self)")
    }
    
    var severity: DiagnosticSeverity { .error }
}
