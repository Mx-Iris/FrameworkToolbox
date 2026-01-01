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
        let accessLevel = try parseArguments(from: node, in: context) ?? "public"
        return [
            """
            \(raw: accessLevel) static var box: FrameworkToolbox<Self>.Type {
                set {}
                get { FrameworkToolbox<Self>.self }
            }
            """,
            """
            \(raw: accessLevel) var box: FrameworkToolbox<Self> {
                set {}
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
    
    
    /// Parses arguments from the attribute syntax.
    private static func parseArguments(from node: AttributeSyntax, in context: some MacroExpansionContext) throws -> String? {
        var access: String?
        
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        
        for arg in arguments {
            // Handle labeled arguments: prefix and suffix
            if let label = arg.label?.text {
                guard let _ = arg.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text else {
                    // You might want to add a diagnostic here for invalid argument types.
                    continue
                }
                switch label {
                default:
                    // Unknown labeled argument
                    break
                }
            }
            // Handle unlabeled argument: access level
            else {
                // The expression should be a member access like `.public`
                guard let memberAccessExpr = arg.expression.as(MemberAccessExprSyntax.self)
//                      let base = memberAccessExpr.base, // The dot
//                      memberAccessExpr.declName.argumentNames == nil
                else { // Ensure it's a simple member, not a function call
                    throw MacroError.invalidAccessLevelArgument(node: arg.expression)
                }
                
                // The access level is the name of the member (e.g., "public")
                access = memberAccessExpr.declName.baseName.text
            }
        }
        
        return access
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
