//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax
import SwiftSyntaxBuilder

/// A type written in an attribute as a metatype: the `String.self` in
/// `@CaseTag(backing: String.self)`.
public struct MetatypeExpression {
    public let type: TypeSyntax

    public init(type: TypeSyntax) {
        self.type = type
    }
}

extension MetatypeExpression: ExpressionDecodable {
    public init(from node: borrowing MemberAccessExprSyntax) throws(ExpressionDecodingError) {
        guard case .keyword(.self) = node.declName.baseName.tokenKind,
              node.declName.argumentNames == nil,
              let base: ExprSyntax = node.base else {
            throw node.expected("a metatype expression such as 'String.self'")
        }

        // A sugared type spelled as a metatype arrives as an *expression*:
        // `[Int].self` parses to an `ArrayExprSyntax`, not an `ArrayTypeSyntax`.
        // Rendering it back to text and reparsing it as a type is the only way
        // to get the type syntax out.
        self.init(type: "\(base.trimmed)")
    }
}
