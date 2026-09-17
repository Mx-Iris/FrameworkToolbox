#if canImport(ObjectiveC)
import Foundation

/// An `NSMutableSet` with its element type written back on.
///
/// As with ``NSMutableArrayOf``, the mutating operations are deliberately not `mutating`
/// — this handle has reference semantics. Also deliberately not `Hashable`, since the
/// contents can change under a stored hash.
@ObjectiveCBridgeable
public struct NSMutableSetOf<Element> {
    public let rawValue: NSMutableSet

    public init(rawValue: NSMutableSet) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: NSMutableSet())
    }

    public init(_ elements: some Sequence<Element>) {
        self.init(rawValue: NSMutableSet(array: Array(elements)))
    }
}

// MARK: - ObjectiveCCollectionHandle

extension NSMutableSetOf: ObjectiveCCollectionHandle {
    public typealias ObjectiveCRepresentation = NSMutableSet

    public static func containsOnlyExpectedElementTypes(in rawValue: NSMutableSet) -> Bool {
        everyObjectMatches(rawValue.objectEnumerator(), as: Element.self)
    }
}

// MARK: - Access and mutation

extension NSMutableSetOf {
    public var count: Int { rawValue.count }

    public var isEmpty: Bool { rawValue.count == 0 }

    /// Membership through `NSSet`'s own hashing — see ``NSSetOf/contains(_:)``.
    public func contains(_ element: Element) -> Bool {
        rawValue.contains(element)
    }

    public var allElements: [Element] {
        rawValue.allObjects.map { storedValue -> Element in expectedElement(storedValue) }
    }

    public func insert(_ element: Element) {
        rawValue.add(element)
    }

    public func insert(contentsOf elements: some Sequence<Element>) {
        rawValue.addObjects(from: Array(elements))
    }

    public func remove(_ element: Element) {
        rawValue.remove(element)
    }

    public func removeAll() {
        rawValue.removeAllObjects()
    }
}

// MARK: - Sequence

extension NSMutableSetOf: Sequence {
    public func makeIterator() -> NSSetOf<Element>.Iterator {
        NSSetOf<Element>(rawValue: rawValue).makeIterator()
    }

    public var underestimatedCount: Int { rawValue.count }
}

// MARK: - Swift set conversion

extension NSMutableSetOf where Element: Hashable {
    public init(_ set: Set<Element>) {
        self.init(rawValue: NSMutableSet(array: Array(set)))
    }

    /// A Swift set holding the same elements. A copy — it shares nothing afterwards.
    public var swiftSet: Set<Element> {
        Set(self)
    }
}

// MARK: - Copying

extension NSMutableSetOf {
    /// An immutable snapshot that no longer shares storage with this one.
    ///
    /// To share instead of copy, use ``NSSetOf/init(sharing:)``.
    public func copy() -> NSSetOf<Element> {
        NSSetOf(rawValue: rawValue.copy() as! NSSet)
    }

    /// A mutable snapshot that no longer shares storage with this one.
    public func mutableCopy() -> NSMutableSetOf<Element> {
        NSMutableSetOf(rawValue: rawValue.mutableCopy() as! NSMutableSet)
    }
}

// MARK: - Conformances

extension NSMutableSetOf: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}

extension NSMutableSetOf: Equatable {
    public static func == (lhs: NSMutableSetOf<Element>, rhs: NSMutableSetOf<Element>) -> Bool {
        lhs.rawValue.isEqual(rhs.rawValue)
    }
}

extension NSMutableSetOf: CustomStringConvertible {
    public var description: String { rawValue.description }
}

extension NSMutableSetOf: CustomDebugStringConvertible {
    public var debugDescription: String { rawValue.debugDescription }
}
#endif
