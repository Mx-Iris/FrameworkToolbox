import Foundation
import Combine

/// Reference-typed runtime backing for the ``UserDefault(key:suite:)`` macro.
///
/// `UserDefaultStorage` owns the `UserDefaults.set/object` calls, an
/// in-memory cache guarded by a recursive lock, and a `PassthroughSubject`
/// that publishes every committed write — including writes that originate
/// from within the same process (system Settings.app via a Settings bundle,
/// another piece of code in the process, another `UserDefaultStorage` over
/// the same suite/key). It is `@unchecked Sendable` because all mutable
/// state is funneled through the lock.
///
/// > Important: `UserDefaults.didChangeNotification` is an **in-process**
/// > notification. Writes made by *another process* to the same app-group
/// > suite are NOT guaranteed to fire this notification, so `publisher` will
/// > not surface them. The Settings.app case works because the Settings
/// > bundle writes through the same per-app `UserDefaults` plist that the
/// > host process re-reads on launch.
///
/// You normally don't instantiate this directly — apply
/// ``UserDefault(key:suite:)`` to a stored property and the macro will emit a
/// `private let _<name> = UserDefaultStorage(...)` for you. The class is
/// public so the macro expansion remains buildable from any module and so
/// power users can compose it manually when they need to.
///
/// ### Semantics
/// - **First read** loads from `UserDefaults`. Missing keys and decoding
///   failures return ``defaultValue``; decoding failures additionally flow
///   through ``errorHandler``.
/// - **Cache** is populated on a successful read or write. Subsequent reads
///   skip `UserDefaults` until the cache is invalidated by an external
///   removal.
/// - **Writes** call `set(_:forKey:)` (or `removeObject(forKey:)` for `nil`
///   on `Optional` values), update the cache up front, and publish the new
///   value through ``publisher`` *after* the lock is released, so a
///   subscriber that re-enters the storage on a different thread won't
///   deadlock.
/// - **External changes** are picked up via `UserDefaults.didChangeNotification`
///   and re-published on ``publisher`` so observers stay in sync with
///   writes from outside this instance.
public final class UserDefaultStorage<Value: UserDefaultStorable>: @unchecked Sendable {
    private let store: UserDefaults
    private let key: String
    private let defaultValue: Value
    private let lock = NSRecursiveLock()
    private var cachedValue: Value?
    private var hasLoadedCache = false
    private let subject = PassthroughSubject<Value, Never>()
    private var _errorHandler: (@Sendable (Error) -> Void)?
    private var observerToken: NSObjectProtocol?
    /// Incremented inside ``set(_:)`` so the synchronously-delivered
    /// `didChangeNotification` callback recognizes its own write and skips
    /// re-publishing. Using a counter (instead of a Bool flag) preserves
    /// correctness if multiple `set(_:)` calls overlap or if a notification
    /// is ever delivered after the writer's lock has been released.
    private var pendingLocalWrites: Int = 0

    public init(
        key: String,
        suite: String? = nil,
        defaultValue: Value,
        errorHandler: (@Sendable (Error) -> Void)? = nil
    ) {
        self._errorHandler = errorHandler

        let resolvedStore: UserDefaults
        var initializationError: UserDefaultError?
        if let suiteName = suite {
            if let custom = UserDefaults(suiteName: suiteName) {
                resolvedStore = custom
            } else {
                resolvedStore = .standard
                initializationError = .unresolvedSuite(suiteName)
            }
        } else {
            resolvedStore = .standard
        }
        self.store = resolvedStore
        self.key = key
        self.defaultValue = defaultValue
        self.observerToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: resolvedStore,
            queue: nil
        ) { [weak self] _ in
            self?.handleExternalChange()
        }

        if let error = initializationError {
            reportError(error)
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    /// Reads the current value, consulting the in-memory cache first.
    ///
    /// Returns ``defaultValue`` when the `UserDefaults` key is absent or the
    /// stored object fails to decode into `Value`.
    public func get() -> Value {
        lock.withLock {
            if hasLoadedCache, let cached = cachedValue {
                return cached
            }

            guard let object = store.object(forKey: key) else {
                return defaultValue
            }
            guard let decoded = Value._decodeStorablePlist(object) else {
                reportError(UserDefaultError.decodingFailed)
                return defaultValue
            }
            cachedValue = decoded
            hasLoadedCache = true
            return decoded
        }
    }

    /// Writes a new value to `UserDefaults` and publishes it.
    ///
    /// When `Value` is `Optional` and the new value is `nil` (at any level
    /// of nesting), the underlying key is deleted via
    /// `removeObject(forKey:)`.
    public func set(_ newValue: Value) {
        // Update cache + dispatch UserDefaults mutation inside the lock. The
        // synchronously-delivered didChangeNotification fires while we still
        // hold the lock; the recursive lock lets the handler reenter and
        // observe pendingLocalWrites > 0, so it skips its own publish.
        lock.withLock {
            cachedValue = newValue
            hasLoadedCache = true

            pendingLocalWrites += 1
            defer { pendingLocalWrites -= 1 }

            if let optional = newValue as? _AnyOptionalStorableValue, optional._isStorableNil {
                store.removeObject(forKey: key)
            } else {
                store.set(newValue._encodeStorablePlist(), forKey: key)
            }
        }

        // Publish AFTER releasing the lock so a subscriber that hops to a
        // different thread and re-enters the storage doesn't deadlock.
        subject.send(newValue)
    }

    /// Publishes every committed write — both writes made through ``set(_:)``
    /// and writes made externally to the same `UserDefaults` suite/key.
    ///
    /// Reading the value via ``get()`` does **not** emit; only successful
    /// writes do.
    ///
    /// The opaque return type intentionally hides the underlying
    /// `PassthroughSubject` so callers can't side-channel `.send(_:)` writes
    /// that bypass `UserDefaults`.
    public var publisher: some Publisher<Value, Never> {
        subject
    }

    /// Optional sink for decode failures encountered during reads. Defaults
    /// to `print(error)`.
    ///
    /// > Note: Suite-resolution failures happen inside ``init(key:suite:defaultValue:errorHandler:)``
    /// > and are routed through whatever handler was supplied to `init`
    /// > (falling back to `print`). Setting this property afterward will
    /// > NOT replay an initialization-time error.
    ///
    /// Set to `nil` to silence all error reporting.
    public var errorHandler: (@Sendable (Error) -> Void)? {
        get { lock.withLock { _errorHandler } }
        set { lock.withLock { _errorHandler = newValue } }
    }

    /// The underlying `UserDefaults` instance backing this storage. Exposed
    /// for diagnostic and testing purposes.
    public var underlyingStore: UserDefaults { store }

    private func handleExternalChange() {
        // Snapshot the value to publish (if any) inside the lock, then send
        // outside the lock — symmetric to set() so subscribers on other
        // threads can re-enter without deadlocking.
        let valueToPublish: Value? = lock.withLock { () -> Value? in
            if pendingLocalWrites > 0 {
                // This notification was triggered by our own set(), which
                // will publish after releasing the lock. Skip.
                return nil
            }

            guard let object = store.object(forKey: key) else {
                // The key was removed by an external writer. Drop the cache
                // so the next get() reflects the new "absent" state, and
                // publish the default value as the observable state.
                cachedValue = nil
                hasLoadedCache = false
                return defaultValue
            }
            guard let decoded = Value._decodeStorablePlist(object) else {
                reportError(UserDefaultError.decodingFailed)
                return nil
            }
            cachedValue = decoded
            hasLoadedCache = true
            return decoded
        }

        if let valueToPublish {
            subject.send(valueToPublish)
        }
    }

    private func reportError(_ error: UserDefaultError) {
        if let handler = _errorHandler {
            handler(error)
        } else {
            print(error)
        }
    }
}
