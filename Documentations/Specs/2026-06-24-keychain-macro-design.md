# `@Keychain` Macro — Design

> **Superseded:** The codec layer (`KeychainStorable` / `KeychainCodableStorable` and the `_decodeKeychainValue` / `_encodeKeychainValue` methods, the `_AnyOptionalKeychainValue` / `_isKeychainNil` dispatch hook, and the `AnyPublisher<Value, Never>` projection type) has since been refactored. See `Documentations/StorageLayer.md` for the current design. Symbol names mentioned in this spec — particularly `_decodeKeychainValue` / `_encodeKeychainValue` → `_decodeStorableData` / `_encodeStorableData`, `_AnyOptionalKeychainValue` → `_AnyOptionalStorableValue`, and `AnyPublisher` → `some Publisher` — are kept here as historical record of the original shipping shape. The high-level motivation, runtime semantics, and Codable opt-in story still apply.

Date: 2026-06-24
Target library: `FoundationToolbox`

## Motivation

The starting point was a property wrapper that combined four concerns:

```swift
@propertyWrapper
public struct Keychain<T: Codable> {
    private let keychain: KeychainAccess.Keychain
    private let subject = PassthroughSubject<T, Never>()
    @RecursiveLock private var _cacheWrappedValue: T?
    // ...
}
```

It read and wrote to the Keychain through [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess), cached the last value behind `@RecursiveLock`, and exposed every committed write via `projectedValue`'s `PassthroughSubject`. The shape worked, but it had three problems:

1. **`mutating get`.** Property wrappers cannot reseat their stored state inside `get` without making the accessor `mutating`. That ruled out using the wrapper on `let`-bound containers, in protocol existentials, or anywhere the property had to be read through a non-mutable reference.
2. **JSON encoding everything.** `JSONEncoder().encode("hello")` is `"\"hello\""`. `JSONEncoder().encode(42)` is `"42"`. Both make a round trip through `Codable`, an allocation chain, and (for strings) string escaping — just to hand a few bytes to `SecItemAdd`. The Keychain stores opaque `Data`; there is no value in routing primitives through JSON.
3. **A third-party dependency for a thin SecItem wrapper.** KeychainAccess provides a polished API surface (sharing, accessibility variants, biometric prompts), but the property wrapper used only the `[data:]` subscript and `synchronizable(true)`. Investigating the KeychainAccess source (`Lib/KeychainAccess/Keychain.swift`) confirmed that even its `String` handling is just `value.data(using: .utf8)` followed by the shared `Data` path — there is no Security framework API specifically for strings to take advantage of.

This design replaces the wrapper with an accessor + peer macro, a hand-rolled `KeychainStorage` runtime that calls `SecItem*` directly, and a `KeychainStorable` protocol that specializes for common primitives while keeping a `Codable` opt-in for user-defined types.

## Goals

- Remove the KeychainAccess dependency.
- Eliminate `mutating get` and the rest of the property-wrapper friction.
- Skip JSON entirely for primitives (`String`, `Data`, `Bool`, the integer and floating-point families, `Date`, `URL`).
- Keep encoded bytes stable across devices when `synchronizable: true`.
- Support `Optional<Wrapped>` so writing `nil` deletes the underlying Keychain item.
- Preserve the publisher-as-projected-value ergonomics: `$myToken` should still vend an `AnyPublisher<Value, Never>`.
- Match the access level of the wrapped property on the generated publisher peer.
- Re-use the existing `LockPropertyParser` so the new macro stays consistent with `@Mutex` / `@OSAllocatedUnfairLock`.

## Non-Goals

- Implementing a fully-featured Keychain client (no access groups, no biometric prompts, no internet-password class). Power users can drop down to `Security.framework` directly when those are needed.
- Compile-time validation of `KeychainStorable` conformance. Swift's generic constraint on `KeychainStorage<Value: KeychainStorable>` is sufficient; a missing conformance produces a normal compiler error at the macro expansion site.
- Cross-process change notifications. The publisher fires only for writes through the same `KeychainStorage` instance. External Keychain mutations are not observed.

## Architecture

### `KeychainStorable` protocol

```swift
public protocol KeychainStorable: Sendable {
    static func _decodeKeychainValue(from data: Data) -> Self?
    func _encodeKeychainValue() -> Data
}
```

Each conformance is a few lines, hand-written to avoid `Codable`:

| Type | Encoding |
|------|----------|
| `String` | `Data(self.utf8)` / `String(data: encoding: .utf8)` |
| `Data` | identity |
| `Bool` | single byte `0x00` / `0x01` |
| `Int8`–`Int64`, `UInt8`–`UInt64` | little-endian, fixed width via `withUnsafeBytes(of: &self.littleEndian)` |
| `Int`, `UInt` | encoded as `Int64` / `UInt64` regardless of host word size |
| `Float`, `Double` | `bitPattern` encoded as the corresponding fixed-width unsigned integer |
| `Date` | `timeIntervalSinceReferenceDate` (`Double`) |
| `URL` | `absoluteString` (`String`) |

Two design choices to call out:

- **Little-endian fixed width.** When `synchronizable: true`, iCloud Keychain may sync values between devices. Encoding `Int` as a native-width little-endian word would silently break the day a 32-bit watchOS device read a 64-bit value (or vice versa). Forcing `Int` and `UInt` through the 8-byte `Int64`/`UInt64` form keeps the bytes interchangeable and the decoding deterministic.
- **`URL` via `absoluteString`.** `URL`'s own NSCoding round-trip serializes more than just the string (path components, base URL, etc.). For Keychain storage we only need a single canonical form, and routing through `String` keeps the encoded bytes identical to what a hand-written entry would look like in the Keychain.

### `KeychainCodableStorable` opt-in

User types opt into JSON storage by adding one conformance:

```swift
struct UserPreferences: KeychainCodableStorable {
    var theme: String
    var notificationsEnabled: Bool
}
```

The default protocol implementation routes encoding through `JSONEncoder`/`JSONDecoder`. There is intentionally no automatic `Codable → KeychainStorable` extension — making the JSON cost explicit keeps users from paying it accidentally on types that should have had a hand-rolled encoding.

### `Optional<Wrapped>` conformance

`Optional` conditionally conforms when `Wrapped` does. The decode path returns `.some(.some(wrapped))` on success — the outer `Optional` is the protocol's "did decoding succeed" signal, the inner one is the actual stored value. The encode path for `.none` returns empty `Data`, but the storage layer short-circuits before reaching it:

```swift
public func set(_ newValue: Value) {
    lock.withLock {
        if let optional = newValue as? _AnyOptionalKeychainValue, optional._isKeychainNil {
            // SecItemDelete + cache update + publisher.send(nil)
            return
        }
        // SecItemUpdate (with SecItemAdd fallback) + cache + send
    }
}
```

`_AnyOptionalKeychainValue` is an internal protocol with a single conformance on `Optional`. It exists purely to type-erase the "is this nil?" check so `KeychainStorage` doesn't need to be specialized for `Optional` separately.

### `KeychainStorage<Value>` runtime

A `final class @unchecked Sendable` that owns:

- A `KeychainItem` struct holding the four query parameters (`account`, `service`, `synchronizable`, `accessible`).
- An in-memory cache (`Value?` plus a `hasLoadedCache: Bool` flag — the flag is needed so that an Optional `Value` whose first-read returned `nil` can still distinguish "cached as nil" from "not yet read").
- An `NSRecursiveLock` that serializes both cache access and SecItem calls.
- A `PassthroughSubject<Value, Never>` that emits on every successful write.
- An optional `errorHandler: (@Sendable (Error) -> Void)?` (defaulting to `print(error)`) that receives `KeychainError` on Security failures.

`KeychainItem` consolidates the three SecItem flows:

- **Read.** Lookup query (`kSecAttrSynchronizable = kSecAttrSynchronizableAny`) plus `kSecReturnData = true`, dispatched through `SecItemCopyMatching`. `errSecItemNotFound` maps to `.notFound`; other failures bubble up as `OSStatus`.
- **Write.** Try `SecItemUpdate` first with the lookup query; on `errSecItemNotFound` fall back to `SecItemAdd` with the full attribute set (specifying the exact `synchronizable` flag and `accessible` policy). This mirrors KeychainAccess's behavior and avoids the "lost item" case where toggling the sync flag between runs would otherwise create duplicates.
- **Delete.** `SecItemDelete` on the lookup query.

`kSecAttrSynchronizableAny` on the lookup path means that an item written with `synchronizable: false` and later read by a `KeychainStorage` configured with `synchronizable: true` will still be found. The exact sync flag is only applied when adding a new item.

### `@Keychain` macro

The macro is declared as a combined accessor + peer macro:

```swift
@attached(accessor)
@attached(peer, names: arbitrary)
public macro Keychain(
    key: String,
    service: String,
    synchronizable: Bool = true,
    accessible: KeychainAccessibility = .whenUnlocked
) = #externalMacro(module: "FoundationToolboxMacros", type: "KeychainMacro")
```

The implementation re-uses `MacroToolbox.LockPropertyParser` to extract the property name, type, initial value, and `static` modifier. The generated peers are:

```swift
private let _<name> = KeychainStorage<Value>(
    /* user-supplied arguments verbatim */,
    defaultValue: <user's initializer>
)

<access modifiers> var $<name>: AnyPublisher<Value, Never> {
    _<name>.publisher
}
```

Three small things worth flagging:

- **Verbatim argument splicing.** The macro's parameter labels (`key`, `service`, `synchronizable`, `accessible`) match `KeychainStorage`'s initializer one-to-one. Rather than manually re-emit each argument (and have to special-case defaults), the macro splices `LabeledExprListSyntax.description` directly into the `KeychainStorage<…>(…)` call. Defaults the user omitted at the macro call site are then filled in by the runtime initializer.
- **`names: arbitrary`.** Both `_<name>` and `$<name>` are generated. `prefixed(_)` covers the storage peer, but `$` isn't accepted as a `prefixed(…)` argument in current `@attached(peer)` syntax, so the macro declares `arbitrary` and emits both names manually.
- **Access-level matching.** The publisher peer copies access-level modifiers (`public`, `package`, `internal`, `fileprivate`, `private`, `open`) from the wrapped variable. A `public var token` produces a `public var $token`. The `_<name>` storage stays `private` regardless so the SecItem dispatch can't be invoked from outside the declaring scope.

### Combine re-export

`AnyPublisher` lives in `Combine`. The macro emits the unqualified name, so `FoundationToolbox/Exported.swift` now `@_exported import`s `Combine` alongside the existing `os` and `SwiftStdlibToolbox` re-exports. Combine is available on every platform the package supports (iOS 13+, macOS 10.15+, etc.), so the import is unconditional.

## Usage

```swift
import FoundationToolbox

final class AuthStore {
    @Keychain(key: "accessToken", service: "com.example.app")
    var accessToken: String = ""

    @Keychain(key: "launchCount", service: "com.example.app", synchronizable: false)
    var launchCount: Int = 0

    // Writing nil deletes the Keychain item.
    @Keychain(key: "refreshToken", service: "com.example.app")
    var refreshToken: String? = nil

    // public on the property → public on $refreshToken too.
    @Keychain(key: "lastSync", service: "com.example.app")
    public var lastSync: Date = .distantPast
}

let store = AuthStore()
let subscription = store.$accessToken.sink { newValue in
    print("token rotated:", newValue)
}

store.accessToken = "abc123"   // writes via SecItemAdd, publishes "abc123"
store.refreshToken = nil       // deletes the Keychain item, publishes nil
```

For Codable types:

```swift
struct UserPreferences: KeychainCodableStorable {
    var theme: String
    var notificationsEnabled: Bool
}

final class PreferencesStore {
    @Keychain(key: "preferences", service: "com.example.app")
    var preferences: UserPreferences = .init(theme: "system", notificationsEnabled: true)
}
```

## Trade-offs

- **Cache is process-local.** Two `KeychainStorage` instances backed by the same key/service don't share a cache and don't observe each other's writes. For a single-process app with one storage instance per property this is fine; multi-process scenarios should either avoid the cache or treat the publisher as best-effort.
- **`@unchecked Sendable`.** All mutable state is lock-guarded, but the compiler can't prove it. The class is marked `@unchecked Sendable` deliberately; the public API is safe to share across actors.
- **Errors are reported, not thrown.** The original property wrapper printed errors and moved on. `KeychainStorage` defaults to the same behavior via `errorHandler` so the macro's accessor stays non-throwing (which is what users want for a `@Keychain` property). Power users can swap `errorHandler` for structured logging.
- **No transactional semantics.** A failed write leaves the cache un-updated and doesn't roll the publisher back. The next read will hit Security again and reflect the real state.

## Migration

Existing call sites that used the old `@Keychain` property wrapper can drop in the macro form unchanged:

```swift
// before — property wrapper, KeychainAccess dependency
@Keychain(key: "accessToken", service: "com.example.app")
var accessToken: String = ""

// after — macro, no KeychainAccess
@Keychain(key: "accessToken", service: "com.example.app")
var accessToken: String = ""
```

The macro's defaults (`synchronizable: true`, `accessible: .whenUnlocked`) match the property wrapper's hard-coded behavior, so stored items remain readable across the upgrade.
