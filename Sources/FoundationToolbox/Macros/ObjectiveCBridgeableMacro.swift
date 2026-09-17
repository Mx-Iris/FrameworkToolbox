#if canImport(ObjectiveC)
import Foundation

/// Generates the `_ObjectiveCBridgeable` conformance for a struct that wraps an Objective-C
/// object in a `rawValue` property.
///
/// ```swift
/// @ObjectiveCBridgeable
/// public struct NSArrayOf<Element>: ObjectiveCCollectionHandle {
///     public let rawValue: NSArray
///     public init(rawValue: NSArray) { self.rawValue = rawValue }
///     public init() { self.init(rawValue: NSArray()) }
///
///     public static func containsOnlyExpectedElementTypes(in rawValue: NSArray) -> Bool {
///         everyObjectMatches(rawValue.objectEnumerator(), as: Element.self)
///     }
/// }
/// ```
///
/// expands to a `_ObjectiveCBridgeable` extension carrying `typealias _ObjectiveCType =
/// NSArray` and the four bridging methods, with `@_semantics("convertToObjectiveC")`,
/// `@_semantics("bridgeFromObjectiveC")` and `@_effects(readonly)` in the right places.
/// Generated members take the attached type's access level.
///
/// ## Requirements
///
/// The attached type must be a **struct** — `_ObjectiveCBridgeable` is only consulted for
/// value types, and a class would have it skipped entirely — and must provide:
///
/// - `var rawValue: <an Objective-C class>`, stored, with an explicit type annotation. The
///   macro reads that annotation syntactically; it becomes `_ObjectiveCType`.
/// - `init(rawValue:)`, and `init()` for the `nil` source the protocol admits.
/// - `static func containsOnlyExpectedElementTypes(in:) -> Bool`, which backs `as?`.
///
/// Conforming to ``ObjectiveCCollectionHandle`` has the compiler check all four up front,
/// rather than surfacing them as errors inside an expansion.
///
/// ## Why the witnesses are generated per type instead of written once
///
/// Because a shared default implementation in a protocol extension silently costs the whole
/// optimization. `objc-bridging-optimization` eliminates a bridge-to-Swift-and-back round
/// trip only when it matches both halves, and it requires a `.directGuaranteed` first
/// argument — which an opaque `Self` in a protocol extension cannot be, since it travels
/// indirectly. Emitting onto the concrete type fixes the calling convention, and the
/// `@_semantics` pair is what makes the pass recognise the functions at all. Both are
/// required: dropping either one returns the round trip to two full calls, with nothing
/// reported anywhere. Verified by reading optimized SIL; see the
/// `objective-c-typed-collections` proposal for the three-way comparison.
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
public macro ObjectiveCBridgeable() = #externalMacro(
    module: "FoundationToolboxMacros",
    type: "ObjectiveCBridgeableMacro"
)
#endif
