#if canImport(ObjectiveC)
import Foundation

/// A typed handle over one of the Objective-C collection classes whose lightweight generic
/// parameters Swift erases on import.
///
/// ## Why the parameters are missing in the first place
///
/// Not because the importer cannot represent them. `shouldSuppressGenericParamsImport` in
/// the compiler's `lib/ClangImporter/ImportDecl.cpp` drops the generic parameters of
/// `NSArray`, `NSDictionary`, `NSSet`, `NSOrderedSet`, `NSEnumerator` and `NSMeasurement`
/// — and of every subclass of theirs — on purpose, and Foundation's API notes pair
/// `SwiftBridge:` with `SwiftImportAsNonGeneric: true` on exactly those classes. The
/// element type is not lost, it *moves*: an Objective-C `NSArray<NSString *> *` arrives in
/// Swift as `[String]`, carrying the parameter with it.
///
/// It only goes missing when the bridge is the thing you must avoid — when reference
/// semantics, object identity or key-value observing are the point and the `NSArray`
/// instance itself has to be what you hold, rather than a Swift copy of its contents.
/// That is what these handles are for.
///
/// ## This protocol describes the shape; ``ObjectiveCBridgeable`` emits the bridge
///
/// The four `_ObjectiveCBridgeable` methods are deliberately **not** default implementations
/// here. They are generated onto each concrete type by `@ObjectiveCBridgeable`, because a
/// witness living in a protocol extension has an opaque `Self`, is therefore passed
/// indirectly, and is consequently invisible to the optimizer pass that eliminates bridging
/// round trips. Keeping a default implementation around would also mean that a type which
/// forgot the macro still compiled — just slower, with nothing to say so.
///
/// ## A conforming type must be a struct
///
/// `_ObjectiveCBridgeable` is only ever consulted for value types, so wrapping the
/// collection in a generic *class* would have the protocol skipped entirely:
///
/// - `tryCastFromObjCBridgeableToClass` in the runtime's `DynamicCast.cpp` only runs when
///   the source is a struct or an enum.
/// - `tryCastFromClassToObjCBridgeable`, the other direction, only runs when the
///   destination is.
/// - `_bridgeAnythingToObjectiveC` documents that a class type "is always bridged verbatim,
///   the function returns `x`".
///
/// ## Reference semantics
///
/// A handle wraps the collection without copying it, so copying the handle shares the
/// underlying object. On the mutable handles the mutating operations are therefore
/// deliberately *not* `mutating`, matching `NSMutableArray` itself: a handle held in a
/// `let` can still add elements, and nothing in the API suggests value semantics.
public protocol ObjectiveCCollectionHandle {
    /// The Objective-C collection class this handle puts an element type back onto.
    associatedtype ObjectiveCCollection: NSObject

    /// Wraps `rawValue` without copying it — the handle and the collection share identity.
    init(rawValue: ObjectiveCCollection)

    /// An empty collection of the wrapped class.
    ///
    /// Needed so that `_unconditionallyBridgeFromObjectiveC` has something to return for the
    /// `nil` source the protocol admits: an Objective-C method declared `nonnull` that
    /// returned `nil` anyway.
    init()

    /// The wrapped Objective-C collection. Bridging hands this exact object back, which is
    /// what keeps object identity — and therefore key-value observing — intact.
    var rawValue: ObjectiveCCollection { get }

    /// Whether every element of `rawValue` matches this handle's element types.
    ///
    /// Backs `as?` and ``init(validating:)``. Linear in the size of the collection, the same
    /// cost `nsArray as? [String]` already pays.
    static func containsOnlyExpectedElementTypes(in rawValue: ObjectiveCCollection) -> Bool
}

// MARK: - Validating construction

extension ObjectiveCCollectionHandle {
    /// Wraps `rawValue` if every element matches this handle's element types, without
    /// copying it. The preferred way to take a collection whose contents you have not
    /// verified.
    ///
    /// `rawValue as? NSArrayOf<String>` reaches the same validation at runtime — pinned by
    /// the bridging tests in both debug and release builds — but it is not the spelling to
    /// reach for. When the source's static type is exactly the wrapped class, the compiler
    /// classifies the cast as an unconditional bridging coercion and reports `conditional
    /// cast from 'NSArray' to 'NSArrayOf<String>' always succeeds` at every such call site.
    /// The diagnostic is wrong about what happens, and right that the language promises
    /// nothing here. This initializer is ordinary Swift with no cast machinery in it, so it
    /// is warning-free and its behaviour is not at the mercy of how a future compiler
    /// classifies the cast.
    public init?(validating rawValue: ObjectiveCCollection) {
        guard Self.containsOnlyExpectedElementTypes(in: rawValue) else { return nil }
        self.init(rawValue: rawValue)
    }
}
#endif
