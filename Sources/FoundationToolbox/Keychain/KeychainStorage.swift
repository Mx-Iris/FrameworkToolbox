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
    private let item: KeychainItem
    private let defaultValue: Value
    private let lock = NSRecursiveLock()
    private var cachedValue: Value?
    private var hasLoadedCache = false
    private let subject = PassthroughSubject<Value, Never>()
    private var _errorHandler: (@Sendable (Error) -> Void)?

    public init(
        key: String,
        service: String,
        synchronizable: Bool = true,
        accessible: KeychainAccessibility = .whenUnlocked,
        defaultValue: Value
    ) {
        self.item = KeychainItem(
            account: key,
            service: service,
            synchronizable: synchronizable,
            accessible: accessible
        )
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

            let readResult = item.read()
            switch readResult {
            case .success(let data):
                if let decoded = Value._decodeKeychainValue(from: data) {
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
        lock.withLock {
            if let optional = newValue as? _AnyOptionalKeychainValue, optional._isKeychainNil {
                switch item.delete() {
                case .success, .notFound:
                    cachedValue = newValue
                    hasLoadedCache = true
                    subject.send(newValue)
                case .failure(let status):
                    reportError(KeychainError.unhandled(status))
                }
                return
            }

            let data = newValue._encodeKeychainValue()
            switch item.write(data) {
            case .success:
                cachedValue = newValue
                hasLoadedCache = true
                subject.send(newValue)
            case .failure(let status):
                reportError(KeychainError.unhandled(status))
            }
        }
    }

    /// Publishes every committed write.
    ///
    /// Reading the value via ``get()`` does **not** emit; only successful
    /// ``set(_:)`` calls do.
    public var publisher: AnyPublisher<Value, Never> {
        subject.eraseToAnyPublisher()
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

// MARK: - SecItem wrapper

private struct KeychainItem {
    let account: String
    let service: String
    let synchronizable: Bool
    let accessible: KeychainAccessibility

    enum ReadResult {
        case success(Data)
        case notFound
        case failure(OSStatus)
    }

    enum WriteResult {
        case success
        case failure(OSStatus)
    }

    enum DeleteResult {
        case success
        case notFound
        case failure(OSStatus)
    }

    func read() -> ReadResult {
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

    func write(_ data: Data) -> WriteResult {
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

    func delete() -> DeleteResult {
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
