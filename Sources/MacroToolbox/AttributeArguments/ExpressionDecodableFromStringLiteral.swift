//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

/// A value written in an attribute as a plain string literal.
///
/// Interpolated literals are rejected: a macro reads its arguments as syntax,
/// long before anything could be interpolated.
public protocol ExpressionDecodableFromStringLiteral:
    ExpressionDecodable<StringLiteralExprSyntax> {
    init?(_ string: String)
}

extension ExpressionDecodableFromStringLiteral {
    public init(from node: borrowing StringLiteralExprSyntax) throws(ExpressionDecodingError) {
        guard case .stringSegment(let segment)? = node.segments.first,
              node.segments.count == 1 else {
            throw node.expected("a string literal")
        }

        guard let value = Self(segment.content.text) else {
            throw node.expected("a valid instance of \(String(reflecting: Self.self))")
        }

        self = value
    }
}
