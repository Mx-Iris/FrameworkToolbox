import Foundation
import Combine
import Security

/// Reference-typed runtime backing for the ``Keychain(_:_:_:_:)`` macro.
///
/// `KeychainStorage` owns the SecItem CRUD, an in-memory cache guarded by a
/// recursive lock, and a `PassthroughSubject` that publishes every committed
/// write. It is `@unchecked Sendable` because all mutable state is funneled
/// through the lock.
///
/// You normally don't instantiate this directly — apply ``Keychain(_:_:_:_:)``
/// to a stored property and the macro will emit a `private let _<name> =
/// KeychainStorage(...)` for you. The class is public so the macro expansion
/// remains buildable from any module and so power users can compose it
/// manually when they need to.
///
/// ### Semantics
/// - **First read** loads from the Keychain. Missing items, decoding failures,
///   or `SecItem*` errors return ``defaultValue`` (and do not cache).
/// - **Cache** is populated on a successful read or write. Subsequent reads
///   skip Security entirely until the process restarts.
/// - **Writes** call `SecItemUpdate`; on `errSecItemNotFound` they fall back
///   to `SecItemAdd`. Errors flow through ``errorHandler``.
/// - **Nil writes** (when `Value` is `Optional`) call `SecItemDelete`, mirror
///   the cache, and publish `nil`.
public final class KeychainStorage<Value: KeychainStorable>: @unchecked Sendable {
    private let backend: any KeychainBackend
    private let defaultValue: Value
    private let lock = NSRecursiveLock()
    private var cachedValue: Value?
    private var hasLoadedCache = false
    private let subject = PassthroughSubject<Value, Never>()
    private var _errorHandler: (@Sendable (Error) -> Void)?

    public convenience init(
        key: String,
        service: String,
        synchronizable: Bool = true,
        accessible: KeychainAccessibility = .whenUnlocked,
        defaultValue: Value
    ) {
        self.init(
            backend: KeychainItem(
                account: key,
                service: service,
                synchronizable: synchronizable,
                accessible: accessible
            ),
            defaultValue: defaultValue
        )
    }

    /// Internal init for tests: injects a custom ``KeychainBackend`` so the
    /// test suite can exercise the runtime without touching the real Keychain
    /// (which would prompt for user authorization, pollute the login
    /// keychain, and fail on machines without entitlements).
    internal init(
        backend: any KeychainBackend,
        defaultValue: Value
    ) {
        self.backend = backend
        self.defaultValue = defaultValue
    }

    /// Reads the current value, consulting the in-memory cache first.
    ///
    /// Returns ``defaultValue`` when the Keychain item is absent, the stored
    /// bytes fail to decode, or the underlying `SecItemCopyMatching` call
    /// fails for any reason other than "not found".
    public func get() -> Value {
        lock.withLock {
            if hasLoadedCache, let cached = cachedValue {
                return cached
            }

            let readResult = backend.read()
            switch readResult {
            case .success(let data):
                if let decoded = Value._decodeStorableData(from: data) {
                    cachedValue = decoded
                    hasLoadedCache = true
                    return decoded
                } else {
                    reportError(KeychainError.decodingFailed)
                    return defaultValue
                }
            case .notFound:
                return defaultValue
            case .failure(let status):
                reportError(KeychainError.unhandled(status))
                return defaultValue
            }
        }
    }

    /// Writes a new value to the Keychain.
    ///
    /// When `Value` is `Optional` and the new value is `nil`, the underlying
    /// item is deleted via `SecItemDelete` and `nil` is published. Otherwise
    /// the encoded bytes are written via `SecItemUpdate` (falling back to
    /// `SecItemAdd`).
    public func set(_ newValue: Value) {
        // Snapshot the value to publish (if any) inside the lock, then send
        // outside the lock so a subscriber that re-enters the storage on a
        // different thread does not deadlock against the lock we are
        // holding.
        let valueToPublish: Value? = lock.withLock { () -> Value? in
            if let optional = newValue as? _AnyOptionalStorableValue, optional._isStorableNil {
                switch backend.delete() {
                case .success, .notFound:
                    cachedValue = newValue
                    hasLoadedCache = true
                    return newValue
                case .failure(let status):
                    reportError(KeychainError.unhandled(status))
                    return nil
                }
            }

            let data = newValue._encodeStorableData()
            switch backend.write(data) {
            case .success:
                cachedValue = newValue
                hasLoadedCache = true
                return newValue
            case .failure(let status):
                reportError(KeychainError.unhandled(status))
                return nil
            }
        }

        if let valueToPublish {
            subject.send(valueToPublish)
        }
    }

    /// Publishes every committed write.
    ///
    /// Reading the value via ``get()`` does **not** emit; only successful
    /// ``set(_:)`` calls do.
    ///
    /// The opaque return type intentionally hides the underlying
    /// `PassthroughSubject` so callers can't side-channel `.send(_:)` writes
    /// that bypass the Keychain.
    public var publisher: some Publisher<Value, Never> {
        subject
    }

    /// Optional sink for Keychain errors. Defaults to `print(error)`.
    ///
    /// Set to `nil` to silence all error reporting.
    public var errorHandler: (@Sendable (Error) -> Void)? {
        get { lock.withLock { _errorHandler } }
        set { lock.withLock { _errorHandler = newValue } }
    }

    private func reportError(_ error: KeychainError) {
        if let handler = _errorHandler {
            handler(error)
        } else {
            print(error)
        }
    }
}

// MARK: - Backend abstraction

/// Internal CRUD-shaped facade over a Keychain item. Lives behind a
/// protocol so tests can inject an in-memory fake without touching
/// Security framework calls (which would prompt for user authorization,
/// pollute the login keychain, and fail on machines without
/// entitlements).
internal protocol KeychainBackend: Sendable {
    func read() -> KeychainReadResult
    func write(_ data: Data) -> KeychainWriteResult
    func delete() -> KeychainDeleteResult
}

internal enum KeychainReadResult: Sendable {
    case success(Data)
    case notFound
    case failure(OSStatus)
}

internal enum KeychainWriteResult: Sendable {
    case success
    case failure(OSStatus)
}

internal enum KeychainDeleteResult: Sendable {
    case success
    case notFound
    case failure(OSStatus)
}

// MARK: - SecItem wrapper

private struct KeychainItem: KeychainBackend {
    let account: String
    let service: String
    let synchronizable: Bool
    let accessible: KeychainAccessibility

    func read() -> KeychainReadResult {
        var query = lookupQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let data = result as? Data {
                return .success(data)
            }
            return .failure(errSecDecode)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failure(status)
        }
    }

    func write(_ data: Data) -> KeychainWriteResult {
        let updateQuery = lookupQuery()
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible.rawValue,
            kSecAttrSynchronizable as String: synchronizable,
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return .success
        case errSecItemNotFound:
            var addQuery = addQuery()
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess ? .success : .failure(addStatus)
        default:
            return .failure(updateStatus)
        }
    }

    func delete() -> KeychainDeleteResult {
        let status = SecItemDelete(lookupQuery() as CFDictionary)
        switch status {
        case errSecSuccess:
            return .success
        case errSecItemNotFound:
            return .notFound
        default:
            return .failure(status)
        }
    }

    /// Query used for read / update / delete. `kSecAttrSynchronizableAny`
    /// matches items regardless of their stored sync flag — this mirrors
    /// KeychainAccess's `ignoringAttributeSynchronizable: true` default and
    /// avoids "lost" items when the synchronizable setting changes between
    /// runs.
    private func lookupQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    /// Attributes used when creating a new item. Specifies the exact
    /// `synchronizable` value rather than `Any`.
    private func addQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
            kSecAttrAccessible as String: accessible.rawValue,
        ]
    }
}
