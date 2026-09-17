#if canImport(ObjectiveC)
import Foundation

// Element access and element validation, shared by every typed collection handle.
//
// Element types are unconstrained on purpose — `NSArrayOf<String>` has to be
// writable, and constraining to `AnyObject` would have ruled it out. Reads and
// writes therefore go through the standard Swift-to-Objective-C bridge:
// `String` lands in the collection as `NSString` and comes back as `String`.
//
// A Swift value type with no Objective-C counterpart is silently boxed in a
// `_SwiftValue` instead. That round-trips correctly within Swift — the box
// unwraps back to the original value — and only Objective-C code sharing the
// collection sees an opaque object.

/// Reads an element out of a collection, or traps with a message explaining what the
/// bare `as!` would have crashed on.
///
/// A failure here is not necessarily a bug in the caller: element types are validated
/// when a handle is built through `as?`, but Objective-C code holding the same object
/// can add anything to it at any time afterwards. Objective-C's own lightweight
/// generics are unsound in exactly the same way.
@inline(__always)
internal func expectedElement<Element>(
    _ storedValue: Any,
    file: StaticString = #fileID,
    line: UInt = #line
) -> Element {
    guard let element = storedValue as? Element else {
        preconditionFailure(
            """
            expected an element of type \(Element.self) but found \(type(of: storedValue)). \
            The underlying Objective-C collection holds a value this handle's type \
            parameter does not describe.
            """,
            file: file,
            line: line
        )
    }
    return element
}

/// Converts a key to the `NSCopying` object `NSMutableDictionary` demands.
///
/// `as AnyObject` performs the standard bridge, and every object it can produce —
/// including the `_SwiftValue` box for an unbridgeable type — conforms to `NSCopying`.
@inline(__always)
internal func expectedDictionaryKey<Key>(
    _ key: Key,
    file: StaticString = #fileID,
    line: UInt = #line
) -> any NSCopying {
    guard let copyingKey = key as AnyObject as? NSCopying else {
        preconditionFailure(
            "a key of type \(Key.self) does not bridge to an object conforming to NSCopying",
            file: file,
            line: line
        )
    }
    return copyingKey
}

/// Whether a type parameter is `Any`, in which case every element matches it and the
/// validation walk can be skipped entirely.
@inline(__always)
@inlinable
internal func matchesEveryElement<Expected>(_ expectedType: Expected.Type) -> Bool {
    expectedType == Any.self
}

/// Whether every object the enumerator yields is an `Expected`.
@inlinable
internal func everyObjectMatches<Expected>(
    _ enumerator: NSEnumerator,
    as expectedType: Expected.Type
) -> Bool {
    if matchesEveryElement(expectedType) { return true }
    while let storedValue = enumerator.nextObject() {
        guard storedValue is Expected else { return false }
    }
    return true
}

/// Whether every key is an `ExpectedKey` and every value an `ExpectedValue`.
///
/// Walks the key enumerator rather than `enumerateKeysAndObjects(_:)` so that the early
/// exit needs no escaping-closure bookkeeping.
@inlinable
internal func everyKeyAndValueMatches<ExpectedKey, ExpectedValue>(
    in dictionary: NSDictionary,
    keyType: ExpectedKey.Type,
    valueType: ExpectedValue.Type
) -> Bool {
    let checksKeys = !matchesEveryElement(keyType)
    let checksValues = !matchesEveryElement(valueType)
    guard checksKeys || checksValues else { return true }

    let keyEnumerator = dictionary.keyEnumerator()
    while let storedKey = keyEnumerator.nextObject() {
        if checksKeys, !(storedKey is ExpectedKey) { return false }
        if checksValues {
            guard let storedValue = dictionary.object(forKey: storedKey),
                  storedValue is ExpectedValue
            else { return false }
        }
    }
    return true
}
#endif
