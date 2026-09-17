#if canImport(ObjectiveC)
import Foundation

/// An `NSArray` with its element type written back on.
///
/// Reaches for the same object rather than a copy of it, so use this where a Swift
/// `[Element]` would be wrong — where the `NSArray` instance itself has to survive the
/// round trip. Where a plain Swift array will do, use a Swift array.
///
/// ```swift
/// let rawArray: NSArray = someObjectiveCAPI()
/// let names = NSArrayOf<String>(rawValue: rawArray)
/// for name in names { print(name.uppercased()) }
///
/// // Or let the bridge validate the element types on the way in:
/// guard let names = rawArray as? NSArrayOf<String> else { return }
/// ```
///
/// Handing the handle to anything typed `Any` or `AnyObject` produces the wrapped
/// `NSArray` itself, not a `_SwiftValue` box around the handle.
///
/// See ``ObjectiveCCollectionHandle`` for why Swift erases the element type to begin
/// with, and why this is a struct rather than a generic class.
@ObjectiveCBridgeable
public struct NSArrayOf<Element> {
    public let rawValue: NSArray

    public init(rawValue: NSArray) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: NSArray())
    }

    public init(_ elements: some Sequence<Element>) {
        self.init(rawValue: NSArray(array: Array(elements)))
    }

    /// Wraps the same object the mutable handle wraps, without copying.
    ///
    /// The result is immutable only in what this handle's API offers — whoever still
    /// holds the mutable handle can go on changing the shared collection.
    public init(sharing mutableHandle: NSMutableArrayOf<Element>) {
        self.init(rawValue: mutableHandle.rawValue)
    }
}

// MARK: - ObjectiveCCollectionHandle

extension NSArrayOf: ObjectiveCCollectionHandle {
    public static func containsOnlyExpectedElementTypes(in rawValue: NSArray) -> Bool {
        everyObjectMatches(rawValue.objectEnumerator(), as: Element.self)
    }
}

// MARK: - Collection

extension NSArrayOf: RandomAccessCollection {
    public var startIndex: Int { 0 }

    public var endIndex: Int { rawValue.count }

    public subscript(position: Int) -> Element {
        expectedElement(rawValue.object(at: position))
    }
}

// MARK: - Copying

extension NSArrayOf {
    /// A snapshot that no longer shares storage with this one.
    public func copy() -> NSArrayOf<Element> {
        NSArrayOf(rawValue: rawValue.copy() as! NSArray)
    }

    /// A mutable snapshot that no longer shares storage with this one.
    public func mutableCopy() -> NSMutableArrayOf<Element> {
        NSMutableArrayOf(rawValue: rawValue.mutableCopy() as! NSMutableArray)
    }
}

// MARK: - Conformances

extension NSArrayOf: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}

extension NSArrayOf: Equatable {
    /// Compares contents through `NSArray.isEqual(_:)`, not object identity — the same
    /// answer Objective-C gives, and a read-only operation on both sides.
    public static func == (lhs: NSArrayOf<Element>, rhs: NSArrayOf<Element>) -> Bool {
        lhs.rawValue.isEqual(rhs.rawValue)
    }
}

extension NSArrayOf: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.hash)
    }
}

extension NSArrayOf: CustomStringConvertible {
    public var description: String { rawValue.description }
}

extension NSArrayOf: CustomDebugStringConvertible {
    public var debugDescription: String { rawValue.debugDescription }
}
#endif
