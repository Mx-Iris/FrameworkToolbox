/// A macro that stores a property's value in the Keychain.
///
/// ```swift
/// @Keychain(key: "accessToken", service: "com.example.app")
/// var accessToken: String = ""
///
/// @Keychain(key: "launchCount", service: "com.example.app")
/// var launchCount: Int = 0
///
/// @Keychain(key: "userToken", service: "com.example.app")
/// var userToken: String? = nil
/// ```
///
/// The macro expands to:
///
/// - A `get`/`set` pair that delegates to a backing
///   ``KeychainStorage`` instance.
/// - A `private let _<name> = KeychainStorage<Value>(...)` peer that owns
///   the Keychain item, an in-memory cache, and a publisher.
/// - A `var $<name>: AnyPublisher<Value, Never>` peer that exposes that
///   publisher under the same access level as the wrapped property.
///
/// Primitives (`String`, `Data`, `Bool`, the integer and floating-point
/// families, `Date`, `URL`) avoid JSON entirely; user-defined types opt into
/// `Codable` storage by conforming to ``KeychainCodableStorable``.
///
/// `Optional<Wrapped>` is supported when `Wrapped: KeychainStorable`. Writing
/// `nil` deletes the underlying Keychain item.
///
/// - Parameters:
///   - key: The account name (`kSecAttrAccount`) under which the value is
///     stored.
///   - service: The service identifier (`kSecAttrService`).
///   - synchronizable: When `true` (the default) the item participates in
///     iCloud Keychain sync. Incompatible with `*ThisDeviceOnly`
///     accessibility classes.
///   - accessible: The `kSecAttrAccessible` policy. Defaults to
///     ``KeychainAccessibility/whenUnlocked``.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro Keychain(
    key: String,
    service: String,
    synchronizable: Bool = true,
    accessible: KeychainAccessibility = .whenUnlocked
) = #externalMacro(module: "FoundationToolboxMacros", type: "KeychainMacro")
