#if canImport(ObjectiveC)
import Foundation

/// An `NSMutableArray` with its element type written back on.
///
/// The mutating operations are deliberately **not** `mutating`, and the subscript setter
/// is `nonmutating`. This handle has reference semantics — it wraps the collection rather
/// than owning a copy of it — and marking the operations `mutating` would dress that up
/// as value semantics it does not have. A handle bound with `let` can still append, just
/// as an `NSMutableArray` held in a `let` can.
///
/// ```swift
/// let names = NSMutableArrayOf<String>()
/// names.append("Ada")           // `let`, and still legal
/// someObjectiveCAPI(names)      // arrives as the wrapped NSMutableArray itself
/// names.append("Grace")         // the Objective-C side observes this
/// ```
///
/// Deliberately not `Hashable`: the contents can change under a stored hash, which would
/// quietly corrupt any `Set` or dictionary key holding it. ``NSArrayOf`` is `Hashable`.
public struct NSMutableArrayOf<Element> {
    public let rawValue: NSMutableArray

    public init(rawValue: NSMutableArray) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: NSMutableArray())
    }

    public init(_ elements: some Sequence<Element>) {
        self.init(rawValue: NSMutableArray(array: Array(elements)))
    }
}

// MARK: - ObjectiveCCollectionHandle

extension NSMutableArrayOf: ObjectiveCCollectionHandle {
    public typealias _ObjectiveCType = NSMutableArray

    public static func containsOnlyExpectedElementTypes(in rawValue: NSMutableArray) -> Bool {
        everyObjectMatches(rawValue.objectEnumerator(), as: Element.self)
    }
}

// MARK: - Collection

extension NSMutableArrayOf: RandomAccessCollection {
    public var startIndex: Int { 0 }

    public var endIndex: Int { rawValue.count }

    public subscript(position: Int) -> Element {
        get { expectedElement(rawValue.object(at: position)) }
        nonmutating set { rawValue.replaceObject(at: position, with: newValue) }
    }
}

// MARK: - Mutation

extension NSMutableArrayOf {
    public func append(_ element: Element) {
        rawValue.add(element)
    }

    public func append(contentsOf elements: some Sequence<Element>) {
        rawValue.addObjects(from: Array(elements))
    }

    public func insert(_ element: Element, at index: Int) {
        rawValue.insert(element, at: index)
    }

    public func remove(at index: Int) {
        rawValue.removeObject(at: index)
    }

    public func removeLast() {
        rawValue.removeLastObject()
    }

    public func removeAll() {
        rawValue.removeAllObjects()
    }

    public func replaceElement(at index: Int, with element: Element) {
        rawValue.replaceObject(at: index, with: element)
    }
}

// MARK: - Copying

extension NSMutableArrayOf {
    /// An immutable snapshot that no longer shares storage with this one.
    ///
    /// To share instead of copy, use ``NSArrayOf/init(sharing:)``.
    public func copy() -> NSArrayOf<Element> {
        NSArrayOf(rawValue: rawValue.copy() as! NSArray)
    }

    /// A mutable snapshot that no longer shares storage with this one.
    public func mutableCopy() -> NSMutableArrayOf<Element> {
        NSMutableArrayOf(rawValue: rawValue.mutableCopy() as! NSMutableArray)
    }
}

// MARK: - Conformances

extension NSMutableArrayOf: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}

extension NSMutableArrayOf: Equatable {
    public static func == (lhs: NSMutableArrayOf<Element>, rhs: NSMutableArrayOf<Element>) -> Bool {
        lhs.rawValue.isEqual(rhs.rawValue)
    }
}

extension NSMutableArrayOf: CustomStringConvertible {
    public var description: String { rawValue.description }
}

extension NSMutableArrayOf: CustomDebugStringConvertible {
    public var debugDescription: String { rawValue.debugDescription }
}
#endif
