#if canImport(ObjectiveC)
import Foundation

/// An `NSMutableDictionary` with its key and value types written back on.
///
/// As with ``NSMutableArrayOf``, the mutating operations are deliberately not `mutating`
/// and the subscript setter is `nonmutating` — this handle has reference semantics, and
/// pretending otherwise would be the lie. Also deliberately not `Hashable`, since the
/// contents can change under a stored hash.
@ObjectiveCBridgeable
public struct NSMutableDictionaryOf<Key, Value> {
    public let rawValue: NSMutableDictionary

    public init(rawValue: NSMutableDictionary) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: NSMutableDictionary())
    }

    public init(keysAndValues: some Sequence<(Key, Value)>) {
        let storage = NSMutableDictionary()
        for (key, value) in keysAndValues {
            storage.setObject(value, forKey: expectedDictionaryKey(key))
        }
        self.init(rawValue: storage)
    }
}

// MARK: - ObjectiveCCollectionHandle

extension NSMutableDictionaryOf: ObjectiveCCollectionHandle {
    public static func containsOnlyExpectedElementTypes(in rawValue: NSMutableDictionary) -> Bool {
        everyKeyAndValueMatches(in: rawValue, keyType: Key.self, valueType: Value.self)
    }
}

// MARK: - Access and mutation

extension NSMutableDictionaryOf {
    public var count: Int { rawValue.count }

    public var isEmpty: Bool { rawValue.count == 0 }

    public subscript(key: Key) -> Value? {
        get {
            guard let storedValue = rawValue.object(forKey: key) else { return nil }
            // Bound explicitly — see the note on `NSDictionaryOf.subscript(_:)`.
            let value: Value = expectedElement(storedValue)
            return value
        }
        nonmutating set {
            if let newValue {
                rawValue.setObject(newValue, forKey: expectedDictionaryKey(key))
            } else {
                rawValue.removeObject(forKey: key)
            }
        }
    }

    public var keys: [Key] {
        rawValue.allKeys.map { storedKey -> Key in expectedElement(storedKey) }
    }

    public var values: [Value] {
        rawValue.allValues.map { storedValue -> Value in expectedElement(storedValue) }
    }

    public func setValue(_ value: Value, for key: Key) {
        rawValue.setObject(value, forKey: expectedDictionaryKey(key))
    }

    public func removeValue(for key: Key) {
        rawValue.removeObject(forKey: key)
    }

    public func removeAll() {
        rawValue.removeAllObjects()
    }
}

// MARK: - Sequence

extension NSMutableDictionaryOf: Sequence {
    public func makeIterator() -> NSDictionaryOf<Key, Value>.Iterator {
        NSDictionaryOf<Key, Value>(rawValue: rawValue).makeIterator()
    }

    public var underestimatedCount: Int { rawValue.count }
}

// MARK: - Swift dictionary conversion

extension NSMutableDictionaryOf where Key: Hashable {
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

extension NSMutableDictionaryOf {
    /// An immutable snapshot that no longer shares storage with this one.
    ///
    /// To share instead of copy, use ``NSDictionaryOf/init(sharing:)``.
    public func copy() -> NSDictionaryOf<Key, Value> {
        NSDictionaryOf(rawValue: rawValue.copy() as! NSDictionary)
    }

    /// A mutable snapshot that no longer shares storage with this one.
    public func mutableCopy() -> NSMutableDictionaryOf<Key, Value> {
        NSMutableDictionaryOf(rawValue: rawValue.mutableCopy() as! NSMutableDictionary)
    }
}

// MARK: - Conformances

extension NSMutableDictionaryOf: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(keysAndValues: elements)
    }
}

extension NSMutableDictionaryOf: Equatable {
    public static func == (
        lhs: NSMutableDictionaryOf<Key, Value>,
        rhs: NSMutableDictionaryOf<Key, Value>
    ) -> Bool {
        lhs.rawValue.isEqual(rhs.rawValue)
    }
}

extension NSMutableDictionaryOf: CustomStringConvertible {
    public var description: String { rawValue.description }
}

extension NSMutableDictionaryOf: CustomDebugStringConvertible {
    public var debugDescription: String { rawValue.debugDescription }
}
#endif
