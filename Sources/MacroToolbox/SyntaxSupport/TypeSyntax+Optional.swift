//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

extension TypeSyntax {
    /// Whether this type is an optional written with the sugared `?` spelling,
    /// looking through attributes and single-element parentheses.
    public var isOptional: Bool {
        if self.is(OptionalTypeSyntax.self) {
            return true
        }
        if let attributed = self.as(AttributedTypeSyntax.self) {
            return attributed.baseType.isOptional
        }
        if let tuple = self.as(TupleTypeSyntax.self),
           tuple.elements.count == 1,
           let onlyElement = tuple.elements.first,
           onlyElement.firstName == nil {
            return onlyElement.type.isOptional
        }
        return false
    }

    /// Whether this type is an optional written the long way, as `Optional<T>`
    /// or `Swift.Optional<T>`.
    ///
    /// A macro cannot resolve types, so it can only match the spelling — which
    /// is why the long form is diagnosed rather than handled.
    public var isUnsugaredOptional: Bool {
        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return identifier.name.unescaped == "Optional"
                && identifier.genericArgumentClause?.arguments.count == 1
        }
        if let member = self.as(MemberTypeSyntax.self) {
            guard member.name.unescaped == "Optional",
                  member.genericArgumentClause?.arguments.count == 1,
                  let base = member.baseType.as(IdentifierTypeSyntax.self) else {
                return false
            }
            return base.name.unescaped == "Swift"
        }
        if let attributed = self.as(AttributedTypeSyntax.self) {
            return attributed.baseType.isUnsugaredOptional
        }
        if let tuple = self.as(TupleTypeSyntax.self),
           tuple.elements.count == 1,
           let onlyElement = tuple.elements.first,
           onlyElement.firstName == nil {
            return onlyElement.type.isUnsugaredOptional
        }
        return false
    }

    /// The warning to emit for a long-form optional, or `nil` when there is
    /// nothing to say. Shaped to be assigned straight into
    /// `context[.warning, type]`.
    public var unsugaredOptionalDiagnostic: String? {
        guard isUnsugaredOptional else {
            return nil
        }
        return """
        spelling '\(self.trimmed)' will not be recognized here; \
        use the sugared optional '?' instead
        """
    }
}
