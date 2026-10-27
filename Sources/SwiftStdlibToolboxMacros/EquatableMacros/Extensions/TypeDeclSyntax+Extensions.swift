import SwiftSyntax

/// Source: https://github.com/ordo-one/equatable

extension TypeDeclSyntax {
    /// Whether the type's own inheritance clause declares `Hashable`, in any of
    /// the spellings that mean it — see ``TypeSyntax/namesHashable``.
    ///
    /// This only sees the declaration the macro is attached to. A conformance it
    /// does not name — declared in an extension elsewhere, implied by a refined
    /// protocol, inherited — is the compiler's to find; see `_EquatableHashing`.
    var declaresHashable: Bool {
        inheritanceClause?.inheritedTypes.contains { $0.type.namesHashable } ?? false
    }
}

extension TypeSyntax {
    /// Whether this type names `Hashable`: plain, as `Swift.Hashable`, behind an
    /// attribute or specifier (`nonisolated Hashable`, `@preconcurrency
    /// Hashable`), or as one member of a composition (`Hashable & Sendable`).
    ///
    /// Missing any of these leaves the compiler to synthesize `hash(into:)` over
    /// every stored property, which then disagrees with the `==` the macro
    /// writes as soon as one property is ignored.
    var namesHashable: Bool {
        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "Hashable"
        }
        if let member = self.as(MemberTypeSyntax.self) {
            return member.name.text == "Hashable"
                && member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift"
        }
        if let attributed = self.as(AttributedTypeSyntax.self) {
            return attributed.baseType.namesHashable
        }
        if let composition = self.as(CompositionTypeSyntax.self) {
            return composition.elements.contains { $0.type.namesHashable }
        }
        return false
    }
}
