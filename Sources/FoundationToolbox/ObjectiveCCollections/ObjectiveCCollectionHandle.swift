#if canImport(ObjectiveC)
import Foundation

/// A typed handle over one of the Objective-C collection classes whose lightweight generic
/// parameters Swift erases on import.
///
/// A specialisation of ``ObjectiveCRepresentable`` for the case where the Swift value wraps
/// the Objective-C object rather than converting to a new one: conform, supply `rawValue`,
/// the two initializers and the element check, and the conversion members come for free from
/// this protocol's extension. Apply ``ObjectiveCBridgeable`` to get the bridge itself.
///
/// ## Why the parameters are missing in the first place
///
/// Not because the importer cannot represent them. `shouldSuppressGenericParamsImport` in
/// the compiler's `lib/ClangImporter/ImportDecl.cpp` drops the generic parameters of
/// `NSArray`, `NSDictionary`, `NSSet`, `NSOrderedSet`, `NSEnumerator` and `NSMeasurement`
/// — and of every subclass of theirs — on purpose, and Foundation's API notes pair
/// `SwiftBridge:` with `SwiftImportAsNonGeneric: true` on exactly those classes. The element
/// type is not lost, it *moves*: an Objective-C `NSArray<NSString *> *` arrives in Swift as
/// `[String]`, carrying the parameter with it.
///
/// It only goes missing when the bridge is the thing you must avoid — when reference
/// semantics, object identity or key-value observing are the point and the `NSArray`
/// instance itself has to be what you hold, rather than a Swift copy of its contents. That
/// is what these handles are for.
///
/// ## Reference semantics
///
/// A handle wraps the collection without copying it, so copying the handle shares the
/// underlying object. On the mutable handles the mutating operations are therefore
/// deliberately *not* `mutating`, matching `NSMutableArray` itself: a handle held in a `let`
/// can still add elements, and nothing in the API suggests value semantics.
public protocol ObjectiveCCollectionHandle: ObjectiveCRepresentable
where ObjectiveCRepresentation: NSObject {
    /// Wraps `rawValue` without copying it — the handle and the collection share identity.
    init(rawValue: ObjectiveCRepresentation)

    /// An empty collection of the wrapped class.
    ///
    /// Stands in when an Objective-C method declared `nonnull` returns `nil` anyway. Unlike
    /// most `ObjectiveCRepresentable` types, a collection has an obvious answer here, so
    /// this protocol supplies one instead of trapping.
    init()

    /// The wrapped Objective-C collection. Bridging hands this exact object back, which is
    /// what keeps object identity — and therefore key-value observing — intact.
    var rawValue: ObjectiveCRepresentation { get }

    /// Whether every element of `rawValue` matches this handle's element types.
    ///
    /// Backs `as?` and ``init(validating:)``. Linear in the size of the collection, the same
    /// cost `nsArray as? [String]` already pays.
    static func containsOnlyExpectedElementTypes(in rawValue: ObjectiveCRepresentation) -> Bool
}

// MARK: - ObjectiveCRepresentable

extension ObjectiveCCollectionHandle {
    /// Hands back the wrapped object itself, so identity survives the round trip.
    public func makeObjectiveCRepresentation() -> ObjectiveCRepresentation {
        rawValue
    }

    public init?(objectiveCRepresentation source: ObjectiveCRepresentation) {
        guard Self.containsOnlyExpectedElementTypes(in: source) else { return nil }
        self.init(rawValue: source)
    }

    /// Wraps without validating, which is the point of this direction: the element check is
    /// linear, and the bridge explicitly allows `as!` to defer it — the same latitude
    /// `nsArray as! [String]` takes.
    public init(uncheckedObjectiveCRepresentation source: ObjectiveCRepresentation) {
        self.init(rawValue: source)
    }

    public static var substituteForMissingObjectiveCRepresentation: Self {
        Self()
    }
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
    public init?(validating rawValue: ObjectiveCRepresentation) {
        self.init(objectiveCRepresentation: rawValue)
    }
}
#endif
