#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Generates a typed, signature-checked caller for a class that is only known
/// by name at runtime.
///
/// ## Overview
///
/// Attach `@RuntimeClassProxy("SomeClassName")` to a `protocol` describing the
/// methods you want to call. A peer `struct` named `<ProtocolName>Implementation`
/// is generated, conforming to the protocol and dispatching each requirement
/// through the host's real implementation.
///
/// A protocol is the vehicle because its requirements have no bodies — the
/// declaration stays plain Swift, with no placeholder implementations to write
/// or explain.
///
/// ## What the generated type does for you
///
/// * Derives each selector from the Swift signature.
/// * Derives each Objective-C type encoding from the Swift types, and checks
///   every one against the live class exactly once, all or nothing. A proxy
///   whose host no longer matches reports itself unusable and logs which method
///   changed and how, rather than marshalling arguments into a signature the
///   host no longer has.
/// * Builds the `@convention(c)` dispatch, so no call site writes
///   `unsafeBitCast` or `perform(_:)` by hand.
/// * Refuses to wrap an object that is not an instance of the named class.
///
/// ## Every returning method returns an optional
///
/// A call into a class that might not be there can always fail, and there is no
/// honest default to invent for a missing method. Modelling that as an optional
/// keeps the failure visible at the call site — write `?? 0` where you want a
/// fallback — instead of hiding it behind a trap or a fabricated zero. A
/// non-optional return type is diagnosed at compile time.
///
/// ## Object ownership
///
/// Object returns are taken through `Unmanaged` and released according to
/// Objective-C's method families: a method in the `alloc`, `new`, `copy` or
/// `mutableCopy` family returns +1 and is consumed with `takeRetainedValue()`;
/// everything else is +0 and uses `takeUnretainedValue()`. Membership follows
/// ARC's naming rule — leading underscores aside, the family's name followed by
/// anything but a lowercase letter — so `_newItem` is +1 and `copyright` is +0.
/// Getting this wrong is the classic way a hand-written proxy over-releases, so
/// it is derived rather than left to the call site.
///
/// A requirement in the `init` family is rejected at compile time: an
/// initialiser takes over the reference to its receiver, and a proxy calls into
/// an object it does not own. Construct such objects with ``DynamicObject``
/// instead — `ObjC.ClassName(...)` sends `alloc` and the initialiser together.
///
/// ## Example
///
/// ```swift
/// @RuntimeClassProxy("Tile")
/// protocol DockTile {
///     var fileURL: URL? { get }
///     func dock() -> AnyObject?
///     func removeReplacementAppImage()
///     func setImage(_ image: AnyObject?, preferredGlassBackgroundStyle: Int)
/// }
///
/// guard let tile = DockTileImplementation(someObject) else { return }
/// tile.removeReplacementAppImage()
/// ```
///
/// - Parameter className: Name of the Objective-C class to call into, resolved
///   with `objc_getClass`.
@attached(peer, names: suffixed(Implementation))
public macro RuntimeClassProxy(_ className: String) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "RuntimeClassProxyMacro"
)

#endif
