#if canImport(ObjectiveC)
import Foundation

/// A Swift value type that has an Objective-C object representation, and knows how to
/// convert in both directions.
///
/// Conform, then apply ``ObjectiveCBridgeable`` to get the `_ObjectiveCBridgeable`
/// conformance generated from these four members. The split is deliberate: this protocol
/// is where the conversion lives and is ordinary, documented, non-underscored API; the
/// macro exists only to emit witnesses that the optimizer can see through, which is
/// something no protocol extension can do (see the macro's documentation for the
/// measurement).
///
/// Nothing here assumes a collection, a wrapper, or a stored property. A conforming type
/// may build its Objective-C representation from scratch, parse one on the way back, or
/// wrap an existing object without copying it.
///
/// ## What conforming buys
///
/// The Swift↔Objective-C bridge starts treating the type as a first-class citizen:
/// `value as AnyObject` produces the Objective-C object rather than an opaque `_SwiftValue`
/// box, `objectiveCObject as? MyType` runs ``init(objectiveCRepresentation:)``, and passing
/// the value to any `Any` or `AnyObject` parameter — `setValue(_:forKey:)`, a notification's
/// `userInfo`, an `NSInvocation` argument — converts it on the way out.
///
/// ## Conformance must be a value type
///
/// `_ObjectiveCBridgeable` is only ever consulted for structs and enums. A class is always
/// bridged verbatim — `_bridgeAnythingToObjectiveC` documents exactly that — so conforming
/// a class would leave every one of these members unused.
public protocol ObjectiveCRepresentable {
    /// The Objective-C class this value converts to and from.
    associatedtype ObjectiveCRepresentation: AnyObject

    /// Converts to Objective-C.
    ///
    /// For a type that wraps an object, returning that same object keeps identity intact
    /// across the round trip — which is what makes key-value observing and mutable
    /// collections shared with Objective-C work at all.
    func makeObjectiveCRepresentation() -> ObjectiveCRepresentation

    /// Converts from Objective-C, **checking completely**, returning `nil` when `source`
    /// cannot represent a `Self`.
    ///
    /// Backs `as?`, which the underlying protocol requires to finish its checking
    /// immediately rather than defer any of it.
    init?(objectiveCRepresentation source: ObjectiveCRepresentation)

    /// Converts from Objective-C, allowed to **defer** checking.
    ///
    /// Backs `as!`. The underlying protocol permits this direction to skip work that
    /// ``init(objectiveCRepresentation:)`` must do — it is what lets `nsArray as! [String]`
    /// avoid walking the elements — so a type with an expensive check should override the
    /// default to take the cheap path.
    init(uncheckedObjectiveCRepresentation source: ObjectiveCRepresentation)

    /// The value to use when an Objective-C method declared `nonnull` hands back `nil`.
    ///
    /// The bridge admits this case because the annotation can lie. Types with a natural
    /// empty value should supply it; the default traps, since most types have none and
    /// silently inventing one hides the API contract violation that got you here.
    static var substituteForMissingObjectiveCRepresentation: Self { get }
}

extension ObjectiveCRepresentable {
    /// Defers nothing — runs the full check and traps if it fails.
    ///
    /// Correct for every conforming type, and the cheapest thing to write; override it when
    /// the full check is expensive and the deferral is worth having.
    @inlinable
    public init(uncheckedObjectiveCRepresentation source: ObjectiveCRepresentation) {
        guard let value = Self(objectiveCRepresentation: source) else {
            preconditionFailure(
                """
                a \(ObjectiveCRepresentation.self) could not be converted to \(Self.self). \
                This came from a forced bridge — `as!`, or an Objective-C API whose \
                signature promised a value of this type.
                """
            )
        }
        self = value
    }

    @inlinable
    public static var substituteForMissingObjectiveCRepresentation: Self {
        preconditionFailure(
            """
            an Objective-C API returned nil where its signature declared \
            \(ObjectiveCRepresentation.self) as nonnull, and \(Self.self) has no value to \
            stand in for it. Conforming types with a natural empty value should override \
            `substituteForMissingObjectiveCRepresentation`.
            """
        )
    }
}
#endif
