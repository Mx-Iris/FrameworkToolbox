//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

/// The failure raised when an attribute's argument *list* cannot be read —
/// an argument is absent, was already consumed, or holds an unusable value.
public enum ExpressionListDecodingError: Error {
    /// Every argument carrying this label has already been decoded. Decoding
    /// the same argument twice is a bug in the macro, not in its caller, and
    /// this case exists to say so rather than silently reporting "missing".
    case consumed(TokenSyntax?, in: TypeSyntax)
    case missing(TokenSyntax?, in: TypeSyntax)
    case invalid(TokenSyntax?, because: ExpressionDecodingError)
}

extension ExpressionListDecodingError: MacroExpansionError {
    public var node: Syntax {
        switch self {
        case .consumed(_, in: let attributeName): Syntax(attributeName)
        case .missing(_, in: let attributeName): Syntax(attributeName)
        case .invalid(_, because: let reason): Syntax(reason.node)
        }
    }
}

extension ExpressionListDecodingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .consumed(let label, in: _):
            """
            could not find any remaining arguments with label '\(label?.text ?? "_")', \
            all matching instances have already been used
            """

        case .missing(let label, in: _):
            """
            could not find expected argument '\(label?.text ?? "_")'
            """

        case .invalid(let label, because: let reason):
            """
            invalid value for argument '\(label?.text ?? "_")', \(reason.description)
            """
        }
    }
}
