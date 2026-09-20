//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// A macro's configuration, read from the arguments written in its attribute.
///
/// Conforming types declare an `ArgumentKey` enumeration whose raw values are
/// the argument labels, then pull each argument out of the decoder. It is the
/// same shape as `Decodable`, and it exists for the same reason: hand-rolled
/// `.as(MemberAccessExprSyntax.self)?.declName.baseName.text` chains swallow
/// every mistake the caller could make instead of diagnosing it.
public protocol ExpressionListDecodable<ArgumentKey> {
    /// The argument labels this configuration understands. An unlabelled
    /// argument is keyed as `_`.
    associatedtype ArgumentKey: Hashable & Sendable & RawRepresentable<String>

    init(from arguments: inout ExpressionListDecoder<ArgumentKey>) throws
}

extension ExpressionListDecodable {
    public init(decoding attribute: borrowing AttributeSyntax) throws {
        var decoder = ExpressionListDecoder<ArgumentKey>(indexing: attribute)
        try self.init(from: &decoder)
    }

    /// Decodes the configuration, or diagnoses why it could not be decoded and
    /// returns `nil` — letting a macro bail out with `guard let` and leave the
    /// caller with a message pointing at the offending argument.
    public init?(
        decoding attribute: borrowing AttributeSyntax,
        in context: some MacroExpansionContext
    ) {
        do {
            self = try Self(decoding: attribute)
        } catch let error as any MacroExpansionError {
            context[.error, error.node] = "\(error)"
            return nil
        } catch {
            context[.error, copy attribute] = "\(error)"
            return nil
        }
    }
}
