//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

/// Indexes the arguments written in a macro attribute by their labels, and
/// hands each one out exactly once.
///
/// Non-copyable so that the "hand out exactly once" bookkeeping cannot be
/// defeated by decoding from a copy.
public struct ExpressionListDecoder<ArgumentKey>: ~Copyable
where ArgumentKey: Hashable & Sendable & RawRepresentable<String> {
    private let attributeName: TypeSyntax
    private var argumentsByKey: [ArgumentKey: ArraySlice<LabeledExprSyntax>]

    private init(
        attributeName: TypeSyntax,
        argumentsByKey: [ArgumentKey: ArraySlice<LabeledExprSyntax>]
    ) {
        self.attributeName = attributeName
        self.argumentsByKey = argumentsByKey
    }
}

extension ExpressionListDecoder {
    public init(indexing attribute: borrowing AttributeSyntax) {
        self.init(attributeName: attribute.attributeName, argumentsByKey: [:])

        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return
        }

        for argument in arguments {
            // An unrecognised label needs no diagnostic of its own: the macro
            // declaration is an ordinary Swift signature, so the compiler has
            // already rejected anything that is not a parameter of it.
            if let key = ArgumentKey(rawValue: argument.label?.text ?? "_") {
                argumentsByKey[key, default: []].append(argument)
            }
        }
    }

    /// The name of the attribute these arguments were written in, for use as
    /// the anchor of a diagnostic about a missing argument.
    public var node: TypeSyntax { attributeName }
}

extension ExpressionListDecoder {
    /// The argument written under `key`, or `nil` when the caller omitted it.
    public subscript(key: ArgumentKey) -> ExpressionListDecoderField<ExprSyntax>? {
        mutating get {
            guard let argument = argumentsByKey[key]?.popFirst() else {
                return nil
            }
            return ExpressionListDecoderField(
                label: argument.label,
                value: argument.expression,
                attributeName: attributeName
            )
        }
    }

    /// The argument written under `key`, as a field that fails on decode when
    /// the caller omitted it.
    ///
    /// The distinction this overload draws, and the reason it cannot simply be
    /// built on the one above: an argument that was never written and one that
    /// has already been decoded look alike once popped, and the second is a bug
    /// in the macro rather than in its caller.
    public subscript(key: ArgumentKey) -> ExpressionListDecoderField<ExprSyntax?> {
        mutating get {
            guard argumentsByKey[key] != nil else {
                return ExpressionListDecoderField(
                    label: nil,
                    value: nil,
                    attributeName: attributeName,
                    isMissing: true
                )
            }

            let argument = argumentsByKey[key]!.popFirst()
            return ExpressionListDecoderField(
                label: argument?.label,
                value: argument?.expression,
                attributeName: attributeName
            )
        }
    }
}
