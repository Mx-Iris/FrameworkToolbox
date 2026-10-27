import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// The two implementations behind `_EquatableHashing`, which `@Equatable` puts on
// the `==` it generates when the type's inheritance clause does not name
// `Hashable`. Which one runs is the compiler's decision, made by overload
// resolution on whether the type is `Hashable` — see the macro declarations.

/// The type is `Hashable`: write the `hash(into:)` that combines exactly the
/// members `==` compares, in the order it compares them.
public enum MatchingHashFunctionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let memberNames = memberNames(in: node)
        guard !memberNames.isEmpty else {
            return ["nonisolated public func hash(into hasher: inout Hasher) {}"]
        }
        return [
            """
            nonisolated public func hash(into hasher: inout Hasher) {
                \(raw: EquatableMacro.hashCombinations(of: memberNames))
            }
            """,
        ]
    }

    /// The names `@Equatable` passed as `members:`.
    private static func memberNames(in node: AttributeSyntax) -> [String] {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let membersArgument = arguments.first(where: { $0.label?.text == "members" }),
              let memberList = membersArgument.expression.as(ArrayExprSyntax.self)
        else {
            return []
        }
        return memberList.elements.compactMap { element in
            element.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        }
    }
}

/// The type is not `Hashable`: nothing to write.
public enum NoHashFunctionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
