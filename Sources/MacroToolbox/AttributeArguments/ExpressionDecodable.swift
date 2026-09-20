//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

/// A Swift value that can be recovered from the expression a caller wrote in
/// a macro attribute — `@Projection(through: "id")` hands `"id"` to
/// `String`'s conformance.
public protocol ExpressionDecodable<Node> {
    /// The kind of expression this type reads itself from. Narrowing it here
    /// rather than accepting `ExprSyntax` is what lets the decoder report
    /// "expected a string literal" before the conforming type ever runs.
    associatedtype Node: ExprSyntaxProtocol

    init(from node: borrowing Node) throws(ExpressionDecodingError)
}

extension ExpressionDecodable where Self: RawRepresentable, RawValue: ExpressionDecodable {
    public init(from node: borrowing RawValue.Node) throws(ExpressionDecodingError) {
        guard let value = Self(rawValue: try .init(from: node)) else {
            throw node.expected("an instance of '\(String(reflecting: Self.self))'")
        }
        self = value
    }
}

extension ExpressionDecodable where Self: LosslessStringConvertible & FixedWidthInteger {
    public init(from node: borrowing ExprSyntax) throws(ExpressionDecodingError) {
        // Only decimal literals are understood; `0x2A` and friends would need
        // their own radix handling.
        let literalText: String

        if let literal = node.as(IntegerLiteralExprSyntax.self),
           case .integerLiteral(let digits) = literal.literal.tokenKind {
            literalText = digits
        } else if let prefixed = node.as(PrefixOperatorExprSyntax.self),
                  let literal = prefixed.expression.as(IntegerLiteralExprSyntax.self),
                  case .prefixOperator(let signOperator) = prefixed.operator.tokenKind,
                  case .integerLiteral(let digits) = literal.literal.tokenKind {
            switch signOperator {
            case "+":
                literalText = digits
            case "-":
                literalText = "\(signOperator)\(digits)"
            default:
                throw ExpressionDecodingError(
                    text: "only '-' and '+' may appear prefixed to an integer literal",
                    node: prefixed.operator
                )
            }
        } else {
            throw node.expected("an integer literal")
        }

        guard let value = Self(literalText) else {
            throw node.expected(
                "integer literal '\(literalText)' overflows '\(String(reflecting: Self.self))'"
            )
        }
        self = value
    }
}
