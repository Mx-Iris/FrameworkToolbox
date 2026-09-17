#if canImport(ObjectiveC)
import Foundation

/// Generates the `_ObjectiveCBridgeable` conformance for a type that conforms to
/// ``ObjectiveCRepresentable``.
///
/// ```swift
/// @ObjectiveCBridgeable
/// public struct Coordinate: ObjectiveCRepresentable {
///     public var latitude: Double
///     public var longitude: Double
///
///     public func makeObjectiveCRepresentation() -> NSValue { ... }
///     public init?(objectiveCRepresentation source: NSValue) { ... }
/// }
/// ```
///
/// The macro assumes nothing about the attached type beyond that conformance. It does not
/// read its properties, does not need to be told the Objective-C class, and every member it
/// writes forwards to an ``ObjectiveCRepresentable`` member — `_ObjectiveCType` is spelled
/// as the protocol's own `ObjectiveCRepresentation`, which the compiler resolves in the
/// concrete type's context. The conversion is yours to define in ordinary, non-underscored
/// API; the macro contributes exactly one thing, and it is not convenience.
///
/// Generated members take the attached type's access level. The type must be a **struct or
/// an enum** — `_ObjectiveCBridgeable` is only consulted for value types, so on a class
/// every generated member would sit unused.
///
/// For the common case of wrapping an Objective-C collection without copying it, conform to
/// ``ObjectiveCCollectionHandle`` instead: it refines ``ObjectiveCRepresentable`` and fills
/// in all four conversion members for you.
///
/// ## The one thing the macro contributes
///
/// Witnesses the optimizer can see through — which no protocol extension can provide.
/// Measured by reading optimized SIL of a bridge-to-Swift-and-straight-back round trip:
///
/// | Witness lives in | `@_semantics` | Round trip |
/// |---|---|---|
/// | protocol extension | present | **not** eliminated |
/// | concrete type | absent | **not** eliminated |
/// | concrete type | present | eliminated, down to `return %0` |
///
/// `objc-bridging-optimization` needs `arguments.count == 2` with a `.directGuaranteed`
/// first argument — an opaque `Self` in a protocol extension travels indirectly and never
/// matches — and it needs both halves annotated to recognise them as a pair. Break either
/// condition and the optimization silently returns to zero with the build still green, which
/// is why this is generated rather than written out once per type.
@attached(
    extension,
    conformances: _ObjectiveCBridgeable,
    names:
        named(_ObjectiveCType),
        named(_bridgeToObjectiveC()),
        named(_forceBridgeFromObjectiveC(_:result:)),
        named(_conditionallyBridgeFromObjectiveC(_:result:)),
        named(_unconditionallyBridgeFromObjectiveC(_:))
)
public macro ObjectiveCBridgeable(inlinable: Bool = false) = #externalMacro(
    module: "FoundationToolboxMacros",
    type: "ObjectiveCBridgeableMacro"
)
#endif
