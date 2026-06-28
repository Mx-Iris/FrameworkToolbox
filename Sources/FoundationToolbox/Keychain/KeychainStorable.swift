import Foundation

/// A type that can be stored in the Keychain through ``KeychainStorage``.
///
/// `KeychainStorable` is a typealias for the shared ``DataStorable`` protocol
/// — anything that can be encoded to / decoded from `Data` can be persisted
/// as a Keychain item's `kSecValueData`. The same codec set is reused by
/// other byte-oriented storage backends; see ``DataStorable`` for the
/// supported primitives and the Codable opt-in.
public typealias KeychainStorable = DataStorable

/// Marker that lets any `Codable` type be stored in the Keychain via the
/// shared JSON-backed default implementation. Typealias of
/// ``DataCodableStorable``.
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
public typealias KeychainCodableStorable = DataCodableStorable
