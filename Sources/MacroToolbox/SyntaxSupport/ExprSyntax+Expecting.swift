//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

extension ExprSyntax {
    /// Narrows this expression to `Expected`, or fails with a message naming
    /// what the caller should have written.
    func expecting<Expected>(
        _: Expected.Type
    ) throws(ExpressionDecodingError) -> Expected where Expected: ExprSyntaxProtocol {
        if let node = self.as(Expected.self) {
            return node
        }

        let expected: String
        switch Expected.self {
        case is NilLiteralExprSyntax.Type:
            expected = "a nil literal"
        case is StringLiteralExprSyntax.Type:
            expected = "a string literal"
        case is BooleanLiteralExprSyntax.Type:
            expected = "a boolean literal"
        case is IntegerLiteralExprSyntax.Type:
            expected = "an integer literal"
        case is ArrayExprSyntax.Type:
            expected = "an array literal"
        case is DictionaryExprSyntax.Type:
            expected = "a dictionary literal"
        case is TupleExprSyntax.Type:
            expected = "a tuple literal"
        case is MemberAccessExprSyntax.Type:
            expected = "a member reference"
        default:
            expected = "an instance of '\(String(reflecting: Expected.self))'"
        }

        throw ExpressionDecodingError(text: "expected \(expected)", node: self)
    }
}

extension ExprSyntaxProtocol {
    func expected(_ what: String) -> ExpressionDecodingError {
        ExpressionDecodingError(text: "expected \(what)", node: self)
    }
}
