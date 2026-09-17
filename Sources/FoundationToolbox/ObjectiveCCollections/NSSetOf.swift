#if canImport(ObjectiveC)
import Foundation

/// An `NSSet` with its element type written back on.
///
/// Wraps the same object rather than a copy of it. See ``ObjectiveCCollectionHandle``
/// for why Swift erases the parameter and why this is a struct.
///
/// `Element` carries no `Hashable` requirement: membership goes through the Objective-C
/// `hash` / `isEqual:` pair on the bridged element, not through Swift hashing.
@ObjectiveCBridgeable
public struct NSSetOf<Element> {
    public let rawValue: NSSet

    public init(rawValue: NSSet) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: NSSet())
    }

    public init(_ elements: some Sequence<Element>) {
        self.init(rawValue: NSSet(array: Array(elements)))
    }

    /// Wraps the same object the mutable handle wraps, without copying.
    public init(sharing mutableHandle: NSMutableSetOf<Element>) {
        self.init(rawValue: mutableHandle.rawValue)
    }
}

// MARK: - ObjectiveCCollectionHandle

extension NSSetOf: ObjectiveCCollectionHandle {
    public static func containsOnlyExpectedElementTypes(in rawValue: NSSet) -> Bool {
        everyObjectMatches(rawValue.objectEnumerator(), as: Element.self)
    }
}

// MARK: - Access

extension NSSetOf {
    public var count: Int { rawValue.count }

    public var isEmpty: Bool { rawValue.count == 0 }

    /// Membership through `NSSet`'s own hashing, so this stays constant time. Shadows the
    /// linear `Sequence.contains(_:)` that an `Equatable` element would otherwise supply.
    public func contains(_ element: Element) -> Bool {
        rawValue.contains(element)
    }

    public var allElements: [Element] {
        rawValue.allObjects.map { storedValue -> Element in expectedElement(storedValue) }
    }
}

// MARK: - Sequence

extension NSSetOf: Sequence {
    public struct Iterator: IteratorProtocol {
        private let objectEnumerator: NSEnumerator

        internal init(objectEnumerator: NSEnumerator) {
            self.objectEnumerator = objectEnumerator
        }

        public mutating func next() -> Element? {
            guard let storedValue = objectEnumerator.nextObject() else { return nil }
            let element: Element = expectedElement(storedValue)
            return element
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(objectEnumerator: rawValue.objectEnumerator())
    }

    public var underestimatedCount: Int { rawValue.count }
}

// MARK: - Swift set conversion

extension NSSetOf where Element: Hashable {
    public init(_ set: Set<Element>) {
        self.init(rawValue: NSSet(array: Array(set)))
    }

    /// A Swift set holding the same elements. A copy — it shares nothing afterwards.
    public var swiftSet: Set<Element> {
        Set(self)
    }
}

// MARK: - Copying

extension NSSetOf {
    /// A snapshot that no longer shares storage with this one.
    public func copy() -> NSSetOf<Element> {
        NSSetOf(rawValue: rawValue.copy() as! NSSet)
    }

    /// A mutable snapshot that no longer shares storage with this one.
    public func mutableCopy() -> NSMutableSetOf<Element> {
        NSMutableSetOf(rawValue: rawValue.mutableCopy() as! NSMutableSet)
    }
}

// MARK: - Conformances

extension NSSetOf: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}

extension NSSetOf: Equatable {
    public static func == (lhs: NSSetOf<Element>, rhs: NSSetOf<Element>) -> Bool {
        lhs.rawValue.isEqual(rhs.rawValue)
    }
}

extension NSSetOf: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.hash)
    }
}

extension NSSetOf: CustomStringConvertible {
    public var description: String { rawValue.description }
}

extension NSSetOf: CustomDebugStringConvertible {
    public var debugDescription: String { rawValue.debugDescription }
}
#endif
