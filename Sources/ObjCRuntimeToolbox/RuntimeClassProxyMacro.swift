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
/// A method or property in the `init` family is rejected at compile time: an
/// initialiser takes over the reference to its receiver, and a proxy calls into
/// an object it does not own. Declare it as an initialiser requirement instead.
///
/// ## Constructing instances
///
/// A failable `init?(…)` requirement sends `+alloc` to the class and the
/// initialiser to what it returned, and wraps the result. The selector is the
/// one Swift imports as that initialiser — `init()` is `init`,
/// `init(frame:level:)` is `initWithFrame:level:` — so the first parameter needs
/// a label. The initialiser is checked with the other requirements, and the
/// references change hands as Objective-C's init family says: `+alloc` hands
/// out one, the initialiser takes it over and hands back its own.
///
/// The initialiser is looked up on the class of the object `+alloc` returned,
/// and checked again there when that is not the named class, so a class
/// cluster whose `+alloc` hands out another class works when the named class
/// implements the initialiser too. One whose named class does not is reported
/// unsupported like any class missing a requirement.
///
/// ## Class methods
///
/// A `static func` or read-only `static var` requirement calls a class method,
/// checked with the other requirements. Ownership follows the method families
/// exactly as for instance methods.
///
/// ## Blocks
///
/// A parameter spelled `@escaping @convention(block) (…) -> …`, or an optional
/// block, is passed as a block and encoded `@?`. It must be able to escape:
/// Objective-C may keep any block it is handed, and a block made from a
/// non-escaping closure traps the process when the callee keeps it. A block
/// cannot be returned.
///
/// ## Example
///
/// ```swift
/// @RuntimeClassProxy("Tile")
/// protocol DockTile {
///     init?(fileURL: URL)
///     static func tileWithFileURL(_ fileURL: URL) -> AnyObject?
///     var fileURL: URL? { get }
///     func dock() -> AnyObject?
///     func removeReplacementAppImage()
///     func setImage(_ image: AnyObject?, preferredGlassBackgroundStyle: Int)
///     func performAfterUpdate(_ handler: @escaping @convention(block) (Bool) -> Void)
/// }
///
/// guard let tile = DockTileImplementation(someObject) else { return }
/// tile.removeReplacementAppImage()
///
/// let newTile = DockTileImplementation(fileURL: applicationURL)
/// ```
///
/// For an object whose class is not known up front — one reached through
/// another object, whose class varies with the operating-system version — use
/// ``RuntimeObjectProxy()``, which checks the class of each object it wraps.
///
/// - Parameter className: Name of the Objective-C class to call into, resolved
///   with `objc_getClass`.
@attached(peer, names: suffixed(Implementation))
public macro RuntimeClassProxy(_ className: String) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "RuntimeClassProxyMacro"
)

#endif
