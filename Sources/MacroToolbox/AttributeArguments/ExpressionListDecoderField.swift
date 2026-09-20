//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

/// One argument pulled out of a macro attribute, still unread.
public struct ExpressionListDecoderField<Value> {
    public let label: TokenSyntax?
    public let value: Value
    private let attributeName: TypeSyntax
    private let isMissing: Bool

    init(
        label: TokenSyntax?,
        value: Value,
        attributeName: TypeSyntax,
        isMissing: Bool = false
    ) {
        self.label = label
        self.value = value
        self.attributeName = attributeName
        self.isMissing = isMissing
    }

    public var name: String { label?.text ?? "_" }
}

extension ExpressionListDecoderField<ExprSyntax> {
    public func decode<Decoded>(
        to _: Decoded.Type = Decoded.self
    ) throws(ExpressionListDecodingError) -> Decoded where Decoded: ExpressionDecodable {
        do {
            return try Decoded(from: try value.expecting(Decoded.Node.self))
        } catch {
            throw .invalid(label, because: error)
        }
    }
}

extension ExpressionListDecoderField<ExprSyntax?> {
    public func decode<Decoded>(
        to _: Decoded.Type = Decoded.self
    ) throws(ExpressionListDecodingError) -> Decoded where Decoded: ExpressionDecodable {
        guard let value else {
            throw isMissing
                ? .missing(label, in: attributeName)
                : .consumed(label, in: attributeName)
        }
        do {
            return try Decoded(from: try value.expecting(Decoded.Node.self))
        } catch {
            throw .invalid(label, because: error)
        }
    }
}
