import Foundation

/// A type that can be stored in `UserDefaults` through ``UserDefaultStorage``.
///
/// `UserDefaultStorable` is a typealias for the shared ``PlistStorable``
/// protocol — anything that can be encoded into a property-list-compatible
/// object can be persisted to a `UserDefaults` suite. The same codec set is
/// reused by other plist-backed storage backends; see ``PlistStorable`` for
/// the supported primitives and the Codable opt-in.
public typealias UserDefaultStorable = PlistStorable

/// Marker that lets any `Codable` type be stored in `UserDefaults` via the
/// shared JSON-backed default implementation. Typealias of
/// ``PlistCodableStorable``.
///
/// ```swift
/// struct UserPreferences: UserDefaultCodableStorable {
///     var theme: String
///     var notificationsEnabled: Bool
/// }
///
/// @UserDefault(key: "prefs")
/// var preferences: UserPreferences = .init(theme: "system", notificationsEnabled: true)
/// ```
public typealias UserDefaultCodableStorable = PlistCodableStorable
