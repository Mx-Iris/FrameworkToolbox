import SwiftSyntax
import SwiftSyntaxBuilder

/// The `$name` projection `@Keychain` and `@UserDefault` generate next to their
/// storage.
enum StoragePublisherProjection {
    /// With a type annotation the projection spells its type out, which keeps
    /// the expansion of every annotated property exactly as it was.
    ///
    /// Without one there is nothing to spell, and a computed property cannot do
    /// without. The projection is then written as an initialized property, and
    /// `_StoragePublisherProjection` turns it into a getter reading the storage,
    /// with the type inferred from the initial value. That initial value is a
    /// prototype rather than the storage itself, and erased to `AnyPublisher`;
    /// the macro's documentation gives the compiler rule behind each. The
    /// subject's `send` stays hidden in both shapes.
    ///
    /// - Parameters:
    ///   - accessModifiers: The property's read access level and its `static`,
    ///     each followed by a space, as they should precede `var`.
    ///   - prototypeStorageExpression: An expression constructing a storage of
    ///     the same type without touching `self`, such as the one the storage
    ///     declaration itself is initialized with.
    static func declaration(
        accessModifiers: String,
        propertyName: String,
        storageName: String,
        valueType: TypeSyntax?,
        prototypeStorageExpression: String
    ) -> DeclSyntax {
        guard let valueType else {
            return """
                @FoundationToolbox._StoragePublisherProjection \(raw: accessModifiers)var $\(raw: propertyName) = \(raw: prototypeStorageExpression).publisher.eraseToAnyPublisher()
                """
        }
        return """
            \(raw: accessModifiers)var $\(raw: propertyName): some Combine.Publisher<\(raw: valueType.trimmedDescription), Never> {
                \(raw: storageName).publisher
            }
            """
    }
}
