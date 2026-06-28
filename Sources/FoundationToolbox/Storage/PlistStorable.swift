import Foundation

/// A type that can be stored as a property-list-compatible object.
///
/// Used by storage backends whose underlying medium understands plist objects
/// natively — most prominently ``UserDefaultStorage``, which calls
/// `UserDefaults.set(_:forKey:)` with the encoded value and decodes the
/// returned `Any` from `object(forKey:)`.
///
/// Conformances split into two layers:
///
/// 1. **Primitives** — `String`, `Data`, `Bool`, the fixed-width integers,
///    `Int`, `UInt`, `Double`, `Float`, `Date`, and `URL` conform directly
///    and round-trip through plist-native types (`NSString`, `NSNumber`,
///    `NSDate`, `NSData`). `URL` round-trips through its `absoluteString` so
///    the value is human-readable in `defaults read` and plist editors.
/// 2. **User-defined `Codable` types** — declare conformance to
///    ``PlistCodableStorable`` and the default implementation encodes via
///    `JSONEncoder` into a `Data` blob.
///
/// `Optional<Wrapped>` conditionally conforms when `Wrapped` does. Storage
/// backends detect a `nil` write via the shared ``_AnyOptionalStorableValue``
/// hook and dispatch to their "delete" path
/// (`UserDefaults.removeObject(forKey:)`) instead of persisting `NSNull`.
///
/// > Important: The value returned by ``_encodeStorablePlist()`` MUST be one
/// > of `String`, `NSNumber`, `Bool`, `Int`, `Double`, `Float`, `Date`,
/// > `Data`, `Array`, or `Dictionary` — anything else will trip an exception
/// > inside `UserDefaults.set(_:forKey:)`.
public protocol PlistStorable: Sendable {
    static func _decodeStorablePlist(_ object: Any) -> Self?
    func _encodeStorablePlist() -> Any
}

// MARK: - Codable opt-in

/// Marker protocol that lets any `Codable` type be stored in a plist-backed
/// store via JSON encoding without manually implementing ``PlistStorable``.
///
/// ```swift
/// struct UserPreferences: PlistCodableStorable {
///     var theme: String
///     var notificationsEnabled: Bool
/// }
///
/// @UserDefault(key: "prefs")
/// var preferences: UserPreferences = .init(theme: "system", notificationsEnabled: true)
/// ```
///
/// The encoded form is `Data` (JSON bytes), which `UserDefaults` accepts
/// directly. `defaults read` will display the bytes; for human-readable
/// debugging consider conforming the type to ``PlistStorable`` manually and
/// returning a `[String: Any]` from ``PlistStorable/_encodeStorablePlist()``.
public protocol PlistCodableStorable: PlistStorable, Codable {}

extension PlistCodableStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Self? {
        guard let data = object as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public func _encodeStorablePlist() -> Any {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

// MARK: - String / Data / Bool

extension String: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> String? {
        object as? String
    }

    public func _encodeStorablePlist() -> Any {
        self
    }
}

extension Data: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Data? {
        object as? Data
    }

    public func _encodeStorablePlist() -> Any {
        self
    }
}

extension Bool: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Bool? {
        if let bool = object as? Bool { return bool }
        if let number = object as? NSNumber { return number.boolValue }
        return nil
    }

    public func _encodeStorablePlist() -> Any {
        self
    }
}

// MARK: - Integer family
//
// All integer conformances round-trip through `NSNumber` (every Swift
// integer bridges to `NSNumber` for `as?`). Narrowing decodes use
// `int64Value` / `uint64Value` piped through `Self.init(exactly:)` so an
// out-of-range stored value surfaces as `nil` (and the storage backend
// reports `decodingFailed`) instead of silently truncating to a bogus
// value.

extension Int: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Int? {
        guard let number = object as? NSNumber else { return nil }
        return Int(exactly: number.int64Value)
    }

    public func _encodeStorablePlist() -> Any {
        self
    }
}

extension UInt: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> UInt? {
        guard let number = object as? NSNumber else { return nil }
        return UInt(exactly: number.uint64Value)
    }

    public func _encodeStorablePlist() -> Any {
        self
    }
}

extension Int64: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Int64? {
        (object as? NSNumber)?.int64Value
    }

    public func _encodeStorablePlist() -> Any {
        NSNumber(value: self)
    }
}

extension UInt64: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> UInt64? {
        (object as? NSNumber)?.uint64Value
    }

    public func _encodeStorablePlist() -> Any {
        NSNumber(value: self)
    }
}

extension Int32: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Int32? {
        guard let number = object as? NSNumber else { return nil }
        return Int32(exactly: number.int64Value)
    }

    public func _encodeStorablePlist() -> Any {
        NSNumber(value: self)
    }
}

extension UInt32: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> UInt32? {
        guard let number = object as? NSNumber else { return nil }
        return UInt32(exactly: number.uint64Value)
    }

    public func _encodeStorablePlist() -> Any {
        NSNumber(value: self)
    }
}

extension Int16: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Int16? {
        guard let number = object as? NSNumber else { return nil }
        return Int16(exactly: number.int64Value)
    }

    public func _encodeStorablePlist() -> Any {
        NSNumber(value: self)
    }
}

extension UInt16: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> UInt16? {
        guard let number = object as? NSNumber else { return nil }
        return UInt16(exactly: number.uint64Value)
    }

    public func _encodeStorablePlist() -> Any {
        NSNumber(value: self)
    }
}

extension Int8: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Int8? {
        guard let number = object as? NSNumber else { return nil }
        return Int8(exactly: number.int64Value)
    }

    public func _encodeStorablePlist() -> Any {
        NSNumber(value: self)
    }
}

extension UInt8: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> UInt8? {
        guard let number = object as? NSNumber else { return nil }
        return UInt8(exactly: number.uint64Value)
    }

    public func _encodeStorablePlist() -> Any {
        NSNumber(value: self)
    }
}

// MARK: - Floating point

extension Double: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Double? {
        (object as? NSNumber)?.doubleValue ?? (object as? Double)
    }

    public func _encodeStorablePlist() -> Any {
        self
    }
}

extension Float: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Float? {
        (object as? NSNumber)?.floatValue ?? (object as? Float)
    }

    public func _encodeStorablePlist() -> Any {
        self
    }
}

// MARK: - Date / URL

extension Date: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Date? {
        object as? Date
    }

    public func _encodeStorablePlist() -> Any {
        self
    }
}

extension URL: PlistStorable {
    /// `URL` round-trips through its `absoluteString` representation so it
    /// stays inspectable in `defaults read` and plist editors. This means
    /// reads via `UserDefaults.url(forKey:)` won't see values written
    /// through ``UserDefaultStorage`` — use the macro projection instead.
    public static func _decodeStorablePlist(_ object: Any) -> URL? {
        guard let string = object as? String else { return nil }
        return URL(string: string)
    }

    public func _encodeStorablePlist() -> Any {
        self.absoluteString
    }
}

// MARK: - Optional

/// Conditional conformance so `var token: String? = nil` is storable.
///
/// The decode path returns `.some(.some(wrapped))` on success — the outer
/// `Optional` is the protocol's "did decoding succeed" signal, the inner one
/// is the actual stored value. The encode path for `.none` returns `NSNull`;
/// storage backends short-circuit before reaching it (via the
/// ``_AnyOptionalStorableValue`` hook) and call `removeObject(forKey:)`
/// instead.
extension Optional: PlistStorable where Wrapped: PlistStorable {
    public static func _decodeStorablePlist(_ object: Any) -> Wrapped?? {
        Wrapped._decodeStorablePlist(object).map(Optional.some)
    }

    public func _encodeStorablePlist() -> Any {
        switch self {
        case .some(let wrapped):
            return wrapped._encodeStorablePlist()
        case .none:
            return NSNull()
        }
    }
}
