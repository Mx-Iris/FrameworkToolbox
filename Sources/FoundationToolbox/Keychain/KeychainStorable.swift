import Foundation

/// A type that can be stored in the Keychain through ``KeychainStorage``.
///
/// Conformances split into two layers:
///
/// 1. **Primitives** — `String`, `Data`, `Bool`, the fixed-width integers,
///    `Int`, `UInt`, `Double`, `Float`, `Date`, and `URL` conform directly,
///    each with a hand-written encoding that avoids JSON entirely.
/// 2. **User-defined `Codable` types** — declare conformance to
///    ``KeychainCodableStorable`` and the protocol's default implementation
///    routes encoding through `JSONEncoder` / `JSONDecoder`.
///
/// `Optional<Wrapped>` conditionally conforms when `Wrapped` does, so
/// `var token: String? = nil` is supported out of the box. In that case
/// writing `nil` deletes the underlying Keychain item; see
/// ``KeychainStorage`` for the runtime semantics.
///
/// > Important: All integer conformances use **little-endian, fixed-width
/// > Int64/UInt64** encoding (regardless of the host's word size). This keeps
/// > values portable when `synchronizable: true` causes the item to sync
/// > across devices via iCloud Keychain. `Double` / `Float` follow the same
/// > convention on their `bitPattern`.
public protocol KeychainStorable: Sendable {
    static func _decodeKeychainValue(from data: Data) -> Self?
    func _encodeKeychainValue() -> Data
}

// MARK: - Codable opt-in

/// Marker protocol that lets any `Codable` type be stored in the Keychain via
/// JSON encoding without manually implementing ``KeychainStorable``.
///
/// ```swift
/// struct UserPreferences: KeychainCodableStorable {
///     var theme: String
///     var notificationsEnabled: Bool
/// }
///
/// @Keychain(key: "prefs", service: "com.example.app")
/// var preferences: UserPreferences = .init(theme: "system", notificationsEnabled: true)
/// ```
public protocol KeychainCodableStorable: KeychainStorable, Codable {}

extension KeychainCodableStorable {
    public static func _decodeKeychainValue(from data: Data) -> Self? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    public func _encodeKeychainValue() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

// MARK: - String / Data / Bool

extension String: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    public func _encodeKeychainValue() -> Data {
        Data(self.utf8)
    }
}

extension Data: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Data? {
        data
    }

    public func _encodeKeychainValue() -> Data {
        self
    }
}

extension Bool: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Bool? {
        guard let byte = data.first else { return nil }
        return byte != 0
    }

    public func _encodeKeychainValue() -> Data {
        Data([self ? 0x01 : 0x00])
    }
}

// MARK: - Integer family (little-endian, fixed width)

extension Int64: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Int64? {
        guard data.count == MemoryLayout<Int64>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
        return Int64(littleEndian: raw)
    }

    public func _encodeKeychainValue() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension UInt64: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> UInt64? {
        guard data.count == MemoryLayout<UInt64>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return UInt64(littleEndian: raw)
    }

    public func _encodeKeychainValue() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension Int32: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Int32? {
        guard data.count == MemoryLayout<Int32>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        return Int32(littleEndian: raw)
    }

    public func _encodeKeychainValue() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension UInt32: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> UInt32? {
        guard data.count == MemoryLayout<UInt32>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return UInt32(littleEndian: raw)
    }

    public func _encodeKeychainValue() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension Int16: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Int16? {
        guard data.count == MemoryLayout<Int16>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        return Int16(littleEndian: raw)
    }

    public func _encodeKeychainValue() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension UInt16: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> UInt16? {
        guard data.count == MemoryLayout<UInt16>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        return UInt16(littleEndian: raw)
    }

    public func _encodeKeychainValue() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension Int8: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Int8? {
        guard data.count == MemoryLayout<Int8>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Int8.self) }
    }

    public func _encodeKeychainValue() -> Data {
        var copy = self
        return Swift.withUnsafeBytes(of: &copy) { Data($0) }
    }
}

extension UInt8: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> UInt8? {
        guard data.count == MemoryLayout<UInt8>.size else { return nil }
        return data.first
    }

    public func _encodeKeychainValue() -> Data {
        Data([self])
    }
}

extension Int: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Int? {
        Int64._decodeKeychainValue(from: data).map { Int(truncatingIfNeeded: $0) }
    }

    public func _encodeKeychainValue() -> Data {
        Int64(self)._encodeKeychainValue()
    }
}

extension UInt: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> UInt? {
        UInt64._decodeKeychainValue(from: data).map { UInt(truncatingIfNeeded: $0) }
    }

    public func _encodeKeychainValue() -> Data {
        UInt64(self)._encodeKeychainValue()
    }
}

// MARK: - Floating point (bit-pattern, little-endian)

extension Double: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Double? {
        UInt64._decodeKeychainValue(from: data).map { Double(bitPattern: $0) }
    }

    public func _encodeKeychainValue() -> Data {
        self.bitPattern._encodeKeychainValue()
    }
}

extension Float: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Float? {
        UInt32._decodeKeychainValue(from: data).map { Float(bitPattern: $0) }
    }

    public func _encodeKeychainValue() -> Data {
        self.bitPattern._encodeKeychainValue()
    }
}

// MARK: - Date / URL

extension Date: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Date? {
        Double._decodeKeychainValue(from: data).map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    public func _encodeKeychainValue() -> Data {
        self.timeIntervalSinceReferenceDate._encodeKeychainValue()
    }
}

extension URL: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> URL? {
        String._decodeKeychainValue(from: data).flatMap { URL(string: $0) }
    }

    public func _encodeKeychainValue() -> Data {
        self.absoluteString._encodeKeychainValue()
    }
}

// MARK: - Optional

/// Conditional conformance so `var token: String? = nil` is storable.
///
/// The decode path returns `.some(.some(wrapped))` on success — the outer
/// `Optional` is the protocol's "did decoding succeed" signal, the inner one
/// is the actual stored value. The encode path for `.none` produces empty
/// `Data`; ``KeychainStorage`` short-circuits before reaching it and deletes
/// the Keychain item instead.
extension Optional: KeychainStorable where Wrapped: KeychainStorable {
    public static func _decodeKeychainValue(from data: Data) -> Wrapped?? {
        Wrapped._decodeKeychainValue(from: data).map(Optional.some)
    }

    public func _encodeKeychainValue() -> Data {
        switch self {
        case .some(let wrapped):
            return wrapped._encodeKeychainValue()
        case .none:
            return Data()
        }
    }
}

// MARK: - Optional dispatch helper

/// Internal type-erased view of `Optional` used by ``KeychainStorage`` to
/// detect a `nil` write and dispatch to `SecItemDelete` instead of storing
/// empty bytes. Kept private to the module so the public surface stays clean.
internal protocol _AnyOptionalKeychainValue {
    var _isKeychainNil: Bool { get }
}

extension Optional: _AnyOptionalKeychainValue {
    internal var _isKeychainNil: Bool {
        switch self {
        case .none: return true
        case .some: return false
        }
    }
}
