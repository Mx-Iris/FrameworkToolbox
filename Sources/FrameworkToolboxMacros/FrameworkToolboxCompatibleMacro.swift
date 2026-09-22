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
        let boxSetter = arguments.hasReferenceSemantics ? "set {}" : "set { self = newValue.base }"
        return [
            """
            \(raw: accessLevel) static var box: FrameworkToolbox<Self>.Type {
                set {}
                get { FrameworkToolbox<Self>.self }
            }
            """,
            """
            \(raw: accessLevel) var box: FrameworkToolbox<Self> {
                \(raw: boxSetter)
                get { FrameworkToolbox(self) }
            }
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
        /// Whether the extended type has reference semantics, which decides
        /// whether the instance `box` setter can write back. See `expansion`.
        var hasReferenceSemantics: Bool = false
    }

    /// Parses arguments from the attribute syntax.
    private static func parseArguments(
        from node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) throws -> Arguments {
        var arguments = Arguments()

        guard let argumentList = node.arguments?.as(LabeledExprListSyntax.self) else {
            return arguments
        }

        for argument in argumentList {
            guard let label = argument.label?.text else {
                // The only unlabelled argument is the access level, written as a
                // member access such as `.public`.
                guard let memberAccessExpression = argument.expression.as(MemberAccessExprSyntax.self) else {
                    throw MacroError.invalidAccessLevelArgument(node: argument.expression)
                }
                arguments.accessLevel = memberAccessExpression.declName.baseName.text
                continue
            }

            switch label {
            case "referenceSemantics":
                guard let booleanLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) else {
                    throw MacroError.invalidReferenceSemanticsArgument(node: argument.expression)
                }
                arguments.hasReferenceSemantics = booleanLiteral.literal.tokenKind == .keyword(.true)
            default:
                break
            }
        }

        return arguments
    }
}

/// Helper to provide diagnostic messages.
private enum MacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case invalidAccessLevelArgument(node: ExprSyntax)
    case invalidReferenceSemanticsArgument(node: ExprSyntax)

    var description: String {
        switch self {
        case .invalidAccessLevelArgument:
            return "Invalid argument for access level. Please use a member of the `AccessLevel` enum, like `.public`."
        case .invalidReferenceSemanticsArgument:
            return "`referenceSemantics:` has to be a boolean literal — it is read at expansion time, so it cannot be a runtime expression."
        }
    }
    
    var message: String { description }
    
    var diagnosticID: MessageID {
        MessageID(domain: "\(FrameworkToolboxCompatibleMacro.self)", id: "\(Self.self)")
    }
    
    var severity: DiagnosticSeverity { .error }
}
