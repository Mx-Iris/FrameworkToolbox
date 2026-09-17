#if canImport(ObjectiveC)
import Foundation

/// An `NSDictionary` with its key and value types written back on.
///
/// Wraps the same object rather than a copy of it. See ``ObjectiveCCollectionHandle``
/// for why Swift erases these parameters and why this is a struct.
///
/// `Key` carries no `Hashable` requirement: lookup goes through the Objective-C
/// `hash` / `isEqual:` pair on the bridged key object, not through Swift hashing. The
/// conversions to and from `[Key: Value]` do require it, and live in a constrained
/// extension.
@ObjectiveCBridgeable(inlinable: true)
public struct NSDictionaryOf<Key, Value> {
    public let rawValue: NSDictionary

    @inlinable
    public init(rawValue: NSDictionary) {
        self.rawValue = rawValue
    }

    @inlinable
    public init() {
        self.init(rawValue: NSDictionary())
    }

    public init(keysAndValues: some Sequence<(Key, Value)>) {
        let storage = NSMutableDictionary()
        for (key, value) in keysAndValues {
            storage.setObject(value, forKey: expectedDictionaryKey(key))
        }
        self.init(rawValue: storage.copy() as! NSDictionary)
    }

    /// Wraps the same object the mutable handle wraps, without copying.
    public init(sharing mutableHandle: NSMutableDictionaryOf<Key, Value>) {
        self.init(rawValue: mutableHandle.rawValue)
    }
}

// MARK: - ObjectiveCCollectionHandle

extension NSDictionaryOf: ObjectiveCCollectionHandle {
    public typealias ObjectiveCRepresentation = NSDictionary

    @inlinable
    public static func containsOnlyExpectedElementTypes(in rawValue: NSDictionary) -> Bool {
        everyKeyAndValueMatches(in: rawValue, keyType: Key.self, valueType: Value.self)
    }
}

// MARK: - Access

extension NSDictionaryOf {
    public var count: Int { rawValue.count }

    public var isEmpty: Bool { rawValue.count == 0 }

    public subscript(key: Key) -> Value? {
        guard let storedValue = rawValue.object(forKey: key) else { return nil }
        // Bound explicitly: inferring the generic parameter from the `Value?` return type
        // would make the cast `as? Value?`, which succeeds for anything at all.
        let value: Value = expectedElement(storedValue)
        return value
    }

    public var keys: [Key] {
        rawValue.allKeys.map { storedKey -> Key in expectedElement(storedKey) }
    }

    public var values: [Value] {
        rawValue.allValues.map { storedValue -> Value in expectedElement(storedValue) }
    }
}

// MARK: - Sequence

extension NSDictionaryOf: Sequence {
    public struct Iterator: IteratorProtocol {
        private let dictionary: NSDictionary
        private let keyEnumerator: NSEnumerator

        internal init(dictionary: NSDictionary) {
            self.dictionary = dictionary
            self.keyEnumerator = dictionary.keyEnumerator()
        }

        public mutating func next() -> (key: Key, value: Value)? {
            guard let storedKey = keyEnumerator.nextObject(),
                  let storedValue = dictionary.object(forKey: storedKey)
            else { return nil }
            let key: Key = expectedElement(storedKey)
            let value: Value = expectedElement(storedValue)
            return (key: key, value: value)
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(dictionary: rawValue)
    }

    public var underestimatedCount: Int { rawValue.count }
}

// MARK: - Swift dictionary conversion

extension NSDictionaryOf where Key: Hashable {
    public init(_ dictionary: [Key: Value]) {
        self.init(keysAndValues: dictionary.map { ($0.key, $0.value) })
    }

    /// A Swift dictionary holding the same pairs. A copy — it shares nothing afterwards.
    public var swiftDictionary: [Key: Value] {
        var result = [Key: Value](minimumCapacity: rawValue.count)
        for (key, value) in self {
            result[key] = value
        }
        return result
    }
}

// MARK: - Copying

extension NSDictionaryOf {
    /// A snapshot that no longer shares storage with this one.
    public func copy() -> NSDictionaryOf<Key, Value> {
        NSDictionaryOf(rawValue: rawValue.copy() as! NSDictionary)
    }

    /// A mutable snapshot that no longer shares storage with this one.
    public func mutableCopy() -> NSMutableDictionaryOf<Key, Value> {
        NSMutableDictionaryOf(rawValue: rawValue.mutableCopy() as! NSMutableDictionary)
    }
}

// MARK: - Conformances

extension NSDictionaryOf: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(keysAndValues: elements)
    }
}

extension NSDictionaryOf: Equatable {
    public static func == (lhs: NSDictionaryOf<Key, Value>, rhs: NSDictionaryOf<Key, Value>) -> Bool {
        lhs.rawValue.isEqual(rhs.rawValue)
    }
}

extension NSDictionaryOf: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.hash)
    }
}

extension NSDictionaryOf: CustomStringConvertible {
    public var description: String { rawValue.description }
}

extension NSDictionaryOf: CustomDebugStringConvertible {
    public var debugDescription: String { rawValue.debugDescription }
}
#endif
