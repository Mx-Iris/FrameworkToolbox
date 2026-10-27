/// A macro that stores a property's value in `UserDefaults`.
///
/// ```swift
/// @UserDefault(key: "username")
/// var username: String = ""
///
/// @UserDefault(key: "launchCount")
/// var launchCount: Int = 0
///
/// @UserDefault(key: "refreshToken", suite: "group.com.example.app")
/// var refreshToken: String? = nil
/// ```
///
/// The macro expands to:
///
/// - A `get` / `set` pair that delegates to a backing
///   ``UserDefaultStorage`` instance.
/// - A `private let _<name> = UserDefaultStorage<Value>(...)` peer that
///   owns the `UserDefaults` reference, an in-memory cache, and a
///   publisher.
/// - A `var $<name>: some Publisher<Value, Never>` peer that exposes that
///   publisher under the same access level as the wrapped property.
///
/// The type annotation is optional when the property has an initial value:
/// `@UserDefault(key: "launchCount") var launchCount = 0` infers `Int` for the
/// property and its storage alike. `$launchCount` is then an
/// `AnyPublisher<Int, Never>` — the compiler does not let a property take its
/// inferred type from another declaration's `some` result — which hides the
/// subject's `send` just the same.
///
/// Primitives (`String`, `Data`, `Bool`, the integer and floating-point
/// families, `Date`, `URL`) round-trip through plist-native types so
/// `defaults read` and plist editors stay useful; user-defined types opt
/// into JSON-backed storage by conforming to ``UserDefaultCodableStorable``.
///
/// `Optional<Wrapped>` is supported when `Wrapped: UserDefaultStorable`.
/// Writing `nil` calls `removeObject(forKey:)`.
///
/// The publisher also reflects **external** writes to the same key (system
/// Settings.app, other code in the process, other processes targeting the
/// same suite via `UserDefaults.didChangeNotification`).
///
/// - Parameters:
///   - key: The `UserDefaults` key under which the value is stored.
///   - suite: The optional suite name (`UserDefaults(suiteName:)`). When
///     `nil` (the default) the value is stored in `UserDefaults.standard`.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro UserDefault(
    key: String,
    suite: String? = nil
) = #externalMacro(module: "FoundationToolboxMacros", type: "UserDefaultMacro")
