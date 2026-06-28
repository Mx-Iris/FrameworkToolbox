import Foundation

/// A type that can be losslessly encoded to / decoded from `Data`.
///
/// Used by storage backends whose underlying medium is raw bytes — most
/// prominently ``KeychainStorage``, which writes the encoded form directly
/// into a Keychain item's `kSecValueData`.
///
/// Conformances split into two layers:
///
/// 1. **Primitives** — `String`, `Data`, `Bool`, the fixed-width integers,
///    `Int`, `UInt`, `Double`, `Float`, `Date`, and `URL` conform directly,
///    each with a hand-written encoding that avoids JSON entirely.
/// 2. **User-defined `Codable` types** — declare conformance to
///    ``DataCodableStorable`` and the protocol's default implementation
///    routes encoding through `JSONEncoder` / `JSONDecoder`.
///
/// `Optional<Wrapped>` conditionally conforms when `Wrapped` does, so
/// `var token: String? = nil` is supported out of the box. Storage backends
/// detect a `nil` write via the internal ``_AnyOptionalStorableValue`` hook
/// and dispatch to their "delete" path rather than persisting empty bytes.
///
/// > Important: All integer conformances use **little-endian, fixed-width
/// > Int64 / UInt64** encoding (regardless of the host's word size). This keeps
/// > values portable when stored bytes are synced across devices (e.g.
/// > iCloud Keychain with `synchronizable: true`). `Double` / `Float` follow
/// > the same convention on their `bitPattern`.
public protocol DataStorable: Sendable {
    static func _decodeStorableData(from data: Data) -> Self?
    func _encodeStorableData() -> Data
}

// MARK: - Codable opt-in

/// Marker protocol that lets any `Codable` type be stored as `Data` via JSON
/// encoding without manually implementing ``DataStorable``.
///
/// ```swift
/// struct UserPreferences: DataCodableStorable {
///     var theme: String
///     var notificationsEnabled: Bool
/// }
///
/// @Keychain(key: "prefs", service: "com.example.app")
/// var preferences: UserPreferences = .init(theme: "system", notificationsEnabled: true)
/// ```
public protocol DataCodableStorable: DataStorable, Codable {}

extension DataCodableStorable {
    public static func _decodeStorableData(from data: Data) -> Self? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    public func _encodeStorableData() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

// MARK: - String / Data / Bool

extension String: DataStorable {
    public static func _decodeStorableData(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    public func _encodeStorableData() -> Data {
        Data(self.utf8)
    }
}

extension Data: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Data? {
        data
    }

    public func _encodeStorableData() -> Data {
        self
    }
}

extension Bool: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Bool? {
        guard let byte = data.first else { return nil }
        return byte != 0
    }

    public func _encodeStorableData() -> Data {
        Data([self ? 0x01 : 0x00])
    }
}

// MARK: - Integer family (little-endian, fixed width)

extension Int64: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Int64? {
        guard data.count == MemoryLayout<Int64>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
        return Int64(littleEndian: raw)
    }

    public func _encodeStorableData() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension UInt64: DataStorable {
    public static func _decodeStorableData(from data: Data) -> UInt64? {
        guard data.count == MemoryLayout<UInt64>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return UInt64(littleEndian: raw)
    }

    public func _encodeStorableData() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension Int32: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Int32? {
        guard data.count == MemoryLayout<Int32>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        return Int32(littleEndian: raw)
    }

    public func _encodeStorableData() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension UInt32: DataStorable {
    public static func _decodeStorableData(from data: Data) -> UInt32? {
        guard data.count == MemoryLayout<UInt32>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return UInt32(littleEndian: raw)
    }

    public func _encodeStorableData() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension Int16: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Int16? {
        guard data.count == MemoryLayout<Int16>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        return Int16(littleEndian: raw)
    }

    public func _encodeStorableData() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension UInt16: DataStorable {
    public static func _decodeStorableData(from data: Data) -> UInt16? {
        guard data.count == MemoryLayout<UInt16>.size else { return nil }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        return UInt16(littleEndian: raw)
    }

    public func _encodeStorableData() -> Data {
        var littleEndian = self.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}

extension Int8: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Int8? {
        guard data.count == MemoryLayout<Int8>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Int8.self) }
    }

    public func _encodeStorableData() -> Data {
        var copy = self
        return Swift.withUnsafeBytes(of: &copy) { Data($0) }
    }
}

extension UInt8: DataStorable {
    public static func _decodeStorableData(from data: Data) -> UInt8? {
        guard data.count == MemoryLayout<UInt8>.size else { return nil }
        return data.first
    }

    public func _encodeStorableData() -> Data {
        Data([self])
    }
}

extension Int: DataStorable {
    /// Decodes the stored `Int64` and narrows to `Int`. Returns `nil` if the
    /// stored value cannot be represented exactly (e.g. a 64-bit value
    /// written on a 64-bit device being read on a 32-bit ABI like watchOS
    /// armv7k); silent truncation would otherwise corrupt the value.
    public static func _decodeStorableData(from data: Data) -> Int? {
        Int64._decodeStorableData(from: data).flatMap(Int.init(exactly:))
    }

    public func _encodeStorableData() -> Data {
        Int64(self)._encodeStorableData()
    }
}

extension UInt: DataStorable {
    /// Decodes the stored `UInt64` and narrows to `UInt`. Returns `nil` if
    /// the stored value overflows `UInt` on the current ABI.
    public static func _decodeStorableData(from data: Data) -> UInt? {
        UInt64._decodeStorableData(from: data).flatMap(UInt.init(exactly:))
    }

    public func _encodeStorableData() -> Data {
        UInt64(self)._encodeStorableData()
    }
}

// MARK: - Floating point (bit-pattern, little-endian)

extension Double: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Double? {
        UInt64._decodeStorableData(from: data).map { Double(bitPattern: $0) }
    }

    public func _encodeStorableData() -> Data {
        self.bitPattern._encodeStorableData()
    }
}

extension Float: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Float? {
        UInt32._decodeStorableData(from: data).map { Float(bitPattern: $0) }
    }

    public func _encodeStorableData() -> Data {
        self.bitPattern._encodeStorableData()
    }
}

// MARK: - Date / URL

extension Date: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Date? {
        Double._decodeStorableData(from: data).map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    public func _encodeStorableData() -> Data {
        self.timeIntervalSinceReferenceDate._encodeStorableData()
    }
}

extension URL: DataStorable {
    public static func _decodeStorableData(from data: Data) -> URL? {
        String._decodeStorableData(from: data).flatMap { URL(string: $0) }
    }

    public func _encodeStorableData() -> Data {
        self.absoluteString._encodeStorableData()
    }
}

// MARK: - Optional

/// Conditional conformance so `var token: String? = nil` is storable.
///
/// The decode path returns `.some(.some(wrapped))` on success — the outer
/// `Optional` is the protocol's "did decoding succeed" signal, the inner one
/// is the actual stored value. The encode path for `.none` produces empty
/// `Data`; storage backends short-circuit before reaching it (via the
/// ``_AnyOptionalStorableValue`` hook) and delete the underlying item instead.
extension Optional: DataStorable where Wrapped: DataStorable {
    public static func _decodeStorableData(from data: Data) -> Wrapped?? {
        Wrapped._decodeStorableData(from: data).map(Optional.some)
    }

    public func _encodeStorableData() -> Data {
        switch self {
        case .some(let wrapped):
            return wrapped._encodeStorableData()
        case .none:
            return Data()
        }
    }
}

// MARK: - Optional dispatch helper

/// Internal type-erased view of `Optional` used by storage backends to detect
/// a `nil` write and dispatch to a "delete" operation (e.g.
/// `SecItemDelete` for Keychain, `UserDefaults.removeObject(forKey:)`) instead
/// of persisting an empty / sentinel value. Kept `internal` to the module so
/// the public surface stays clean.
///
/// Shared by both ``DataStorable`` and ``PlistStorable`` consumers — a
/// `nil` `Optional` is `nil` regardless of the encoding medium.
internal protocol _AnyOptionalStorableValue {
    var _isStorableNil: Bool { get }
}

extension Optional: _AnyOptionalStorableValue {
    /// `true` if `self` is `.none` at any level of an Optional chain.
    ///
    /// This intentionally recurses so a nested-Optional `.some(.none)` (e.g.
    /// `Optional<Optional<String>>.some(.none)`) is also reported as nil.
    /// Without recursion, the storage backend's short-circuit would miss
    /// inner nils and either crash (NSNull reaching `UserDefaults.set`) or
    /// silently corrupt data (empty `Data` round-tripping through
    /// `String._decodeStorableData` as `""`).
    internal var _isStorableNil: Bool {
        switch self {
        case .none:
            return true
        case .some(let wrapped):
            if let nested = wrapped as? _AnyOptionalStorableValue {
                return nested._isStorableNil
            }
            return false
        }
    }
}
