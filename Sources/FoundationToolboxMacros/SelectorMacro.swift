import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

public struct SelectorMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        return #"NSSelectorFromString("")"#
    }
}

enum SelectorMacroError: Error, CustomStringConvertible {
    case noArguments
    case mustBeValidStringLiteral
    case containsWhitespaceOrEmpty

    var description: String {
        switch self {
        case .noArguments:
            return "The macro does not have any arguments"
        case .mustBeValidStringLiteral:
            return "Argument must be a string literal"
        case .containsWhitespaceOrEmpty:
            return "Selector string must be non-empty and must not contain whitespace"
        }
    }
}
