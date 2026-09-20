//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

/// The failure raised when a single attribute argument cannot be read as the
/// Swift value a macro expected.
public struct ExpressionDecodingError: Error {
    public let text: String
    public let node: Syntax

    public init(text: String, node: some SyntaxProtocol) {
        self.text = text
        self.node = Syntax(node)
    }
}

extension ExpressionDecodingError: MacroExpansionError {}

extension ExpressionDecodingError: CustomStringConvertible {
    public var description: String { text }
}
