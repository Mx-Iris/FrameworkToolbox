#if canImport(ObjectiveC)
import Foundation

/// A typed handle over one of the Objective-C collection classes whose
/// lightweight generic parameters Swift erases on import.
///
/// ## Why the parameters are missing in the first place
///
/// Not because the importer cannot represent them. `shouldSuppressGenericParamsImport`
/// in the compiler's `lib/ClangImporter/ImportDecl.cpp` drops the generic parameters of
/// `NSArray`, `NSDictionary`, `NSSet`, `NSOrderedSet`, `NSEnumerator` and `NSMeasurement`
/// — and of every subclass of theirs — on purpose, and Foundation's API notes pair
/// `SwiftBridge:` with `SwiftImportAsNonGeneric: true` on exactly those classes. The
/// element type is not lost, it *moves*: an Objective-C `NSArray<NSString *> *` arrives
/// in Swift as `[String]`, carrying the parameter with it.
///
/// It only goes missing when the bridge is the thing you must avoid — when reference
/// semantics, object identity or key-value observing are the point and the `NSArray`
/// instance itself has to be what you hold, rather than a Swift copy of its contents.
/// That is what these handles are for.
///
/// ## A conforming type must be a struct
///
/// `_ObjectiveCBridgeable` is only ever consulted for value types, so wrapping the
/// collection in a generic *class* would have the protocol skipped entirely:
///
/// - `tryCastFromObjCBridgeableToClass` in the runtime's `DynamicCast.cpp` only runs
///   when the source is a struct or an enum.
/// - `tryCastFromClassToObjCBridgeable`, the other direction, only runs when the
///   destination is.
/// - `_bridgeAnythingToObjectiveC` documents that a class type "is always bridged
///   verbatim, the function returns `x`".
///
/// ## Reference semantics
///
/// A handle wraps the collection without copying it, so copying the handle shares the
/// underlying object. On the mutable handles the mutating operations are therefore
/// deliberately *not* `mutating`, matching `NSMutableArray` itself: a handle held in a
/// `let` can still add elements, and nothing in the API suggests value semantics.
public protocol ObjectiveCCollectionHandle: _ObjectiveCBridgeable where _ObjectiveCType: NSObject {
    /// Wraps `rawValue` without copying it — the handle and the collection share identity.
    init(rawValue: _ObjectiveCType)

    /// An empty collection of the wrapped class.
    ///
    /// Only needed so that `_unconditionallyBridgeFromObjectiveC` has something to return
    /// for the `nil` source the protocol admits: an Objective-C method declared `nonnull`
    /// that returned `nil` anyway.
    init()

    /// The wrapped Objective-C collection. Bridging hands this exact object back, which is
    /// what keeps object identity — and therefore key-value observing — intact.
    var rawValue: _ObjectiveCType { get }

    /// Whether every element of `rawValue` matches this handle's element types.
    ///
    /// Backs `as?`, which the protocol requires to complete its checking immediately
    /// rather than defer it. Linear in the size of the collection, the same cost
    /// `nsArray as? [String]` already pays.
    static func containsOnlyExpectedElementTypes(in rawValue: _ObjectiveCType) -> Bool
}

// MARK: - Validating construction

extension ObjectiveCCollectionHandle {
    /// Wraps `rawValue` if every element matches this handle's element types, without
    /// copying it. The preferred way to take a collection whose contents you have not
    /// verified.
    ///
    /// `rawValue as? NSArrayOf<String>` reaches the same validation at runtime — pinned by
    /// the bridging tests in both debug and release builds — but it is not the spelling to
    /// reach for. When the source's static type is exactly the `_ObjectiveCType`, the
    /// compiler classifies the cast as an unconditional bridging coercion and reports
    /// `conditional cast from 'NSArray' to 'NSArrayOf<String>' always succeeds` at every
    /// such call site. The diagnostic is wrong about what happens, and right that the
    /// language promises nothing here. This initializer is ordinary Swift with no cast
    /// machinery in it, so it is warning-free and its behaviour is not at the mercy of how
    /// a future compiler classifies the cast.
    public init?(validating rawValue: _ObjectiveCType) {
        guard Self.containsOnlyExpectedElementTypes(in: rawValue) else { return nil }
        self.init(rawValue: rawValue)
    }
}

// MARK: - Bridging

extension ObjectiveCCollectionHandle {
    public func _bridgeToObjectiveC() -> _ObjectiveCType {
        rawValue
    }

    public static func _forceBridgeFromObjectiveC(_ source: _ObjectiveCType, result: inout Self?) {
        // The protocol explicitly allows this direction to defer element checking — it is
        // what lets `nsArray as! [String]` avoid a walk — so no validation here.
        result = Self(rawValue: source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(
        _ source: _ObjectiveCType,
        result: inout Self?
    ) -> Bool {
        guard containsOnlyExpectedElementTypes(in: source) else {
            result = nil
            return false
        }
        result = Self(rawValue: source)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: _ObjectiveCType?) -> Self {
        guard let source else { return Self() }
        return Self(rawValue: source)
    }
}
#endif
