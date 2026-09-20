//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

// MARK: - String-literal-backed values

extension String: ExpressionDecodableFromStringLiteral {}
extension Substring: ExpressionDecodableFromStringLiteral {}
extension Character: ExpressionDecodableFromStringLiteral {}
extension Unicode.Scalar: ExpressionDecodableFromStringLiteral {}

// MARK: - Literal-backed values

extension Bool: ExpressionDecodable {
    public init(from node: borrowing BooleanLiteralExprSyntax) {
        if case .keyword(.true) = node.literal.tokenKind {
            self = true
        } else {
            self = false
        }
    }
}

extension Int: ExpressionDecodable {}
extension Int8: ExpressionDecodable {}
extension Int16: ExpressionDecodable {}
extension Int32: ExpressionDecodable {}
extension Int64: ExpressionDecodable {}
extension UInt: ExpressionDecodable {}
extension UInt8: ExpressionDecodable {}
extension UInt16: ExpressionDecodable {}
extension UInt32: ExpressionDecodable {}
extension UInt64: ExpressionDecodable {}

// MARK: - Composites

extension Optional: ExpressionDecodable where Wrapped: ExpressionDecodable {
    public init(from node: borrowing ExprSyntax) throws(ExpressionDecodingError) {
        if node.is(NilLiteralExprSyntax.self) {
            self = nil
        } else {
            self = try Wrapped(from: try node.expecting(Wrapped.Node.self))
        }
    }
}

extension Array: ExpressionDecodable where Element: ExpressionDecodable {
    public init(from node: borrowing ArrayExprSyntax) throws(ExpressionDecodingError) {
        self = try node.elements.map { element throws(ExpressionDecodingError) in
            try Element(from: try element.expression.expecting(Element.Node.self))
        }
    }
}

extension Set: ExpressionDecodable where Element: ExpressionDecodable {
    public init(from node: borrowing ArrayExprSyntax) throws(ExpressionDecodingError) {
        self = []
        for element in node.elements {
            let decoded = try Element(
                from: try element.expression.expecting(Element.Node.self)
            )
            guard update(with: decoded) == nil else {
                throw ExpressionDecodingError(
                    text: "expected a set literal with unique elements",
                    node: element.expression
                )
            }
        }
    }
}

/// Present so that `Never` can stand in as the decoded type of an argument a
/// macro accepts only as `nil`. Decoding one always fails.
extension Never: ExpressionDecodable {
    public init(from node: borrowing NilLiteralExprSyntax) throws(ExpressionDecodingError) {
        throw ExpressionDecodingError(text: "unexpected value", node: copy node)
    }
}
