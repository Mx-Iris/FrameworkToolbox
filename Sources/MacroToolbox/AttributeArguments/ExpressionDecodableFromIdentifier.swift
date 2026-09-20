//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

/// A value written in an attribute with leading-dot syntax, the way an enum
/// case is spelled at a call site: `@Something(level: .public)`.
public protocol ExpressionDecodableFromIdentifier: ExpressionDecodable {
    init(base: ExprSyntax?, name: TokenSyntax) throws(ExpressionDecodingError)
}

extension ExpressionDecodableFromIdentifier {
    public init(from node: borrowing MemberAccessExprSyntax) throws(ExpressionDecodingError) {
        guard node.declName.argumentNames == nil else {
            throw node.expected("a bare property reference")
        }

        try self.init(base: node.base, name: node.declName.baseName)
    }
}

extension ExpressionDecodableFromIdentifier where Self: RawRepresentable<String> {
    public init(base: ExprSyntax?, name: TokenSyntax) throws(ExpressionDecodingError) {
        if let base {
            throw ExpressionDecodingError(
                text: "enum case expression must be written with leading dot syntax",
                node: base
            )
        }
        guard let value = Self(rawValue: name.text) else {
            throw ExpressionDecodingError(
                text: "expected a case of '\(String(reflecting: Self.self))'",
                node: name
            )
        }

        self = value
    }
}
