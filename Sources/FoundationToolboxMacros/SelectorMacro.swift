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
        guard let argument = node.arguments.first else {
            throw SelectorMacroError.noArguments
        }

        guard let stringLiteralExpr = argument.expression.as(StringLiteralExprSyntax.self),
              stringLiteralExpr.segments.count == 1,
              let segment = stringLiteralExpr.segments.first?.as(StringSegmentSyntax.self)
        else {
            throw SelectorMacroError.mustBeValidStringLiteral
        }

        let text = segment.content.text

        guard !text.isEmpty,
              text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw SelectorMacroError.containsWhitespaceOrEmpty
        }

        return #"NSSelectorFromString("\#(raw: text)")"#
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
