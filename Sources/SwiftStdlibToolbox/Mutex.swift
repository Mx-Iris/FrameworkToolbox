import struct os.os_unfair_lock_t
import struct os.os_unfair_lock
import func os.os_unfair_lock_lock
import func os.os_unfair_lock_unlock
import func os.os_unfair_lock_trylock

@frozen
public struct Mutex<Value: ~Copyable>: ~Copyable {
    @usableFromInline
    let storage: Storage<Value>

    @_alwaysEmitIntoClient
    @_transparent
    public init(_ initialValue: consuming sending Value) {
        self.storage = Storage(initialValue)
    }

    @_alwaysEmitIntoClient
    @_transparent
    public borrowing func withLock<Result, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending Result
    ) throws(E) -> sending Result {
        storage.lock()
        defer { storage.unlock() }
        return try body(&storage.value)
    }

    @_alwaysEmitIntoClient
    @_transparent
    public borrowing func withLockIfAvailable<Result, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending Result
    ) throws(E) -> sending Result? {
        guard storage.tryLock() else { return nil }
        defer { storage.unlock() }
        return try body(&storage.value)
    }
}

extension Mutex: @unchecked Sendable where Value: ~Copyable {}

@usableFromInline
final class Storage<Value: ~Copyable> {
    private let _lock: os_unfair_lock_t

    @usableFromInline
    var value: Value

    @usableFromInline
    init(_ initialValue: consuming Value) {
        self._lock = .allocate(capacity: 1)
        _lock.initialize(to: os_unfair_lock())
        self.value = initialValue
    }

    @usableFromInline
    func lock() {
        os_unfair_lock_lock(_lock)
    }

    @usableFromInline
    func unlock() {
        os_unfair_lock_unlock(_lock)
    }

    @usableFromInline
    func tryLock() -> Bool {
        os_unfair_lock_trylock(_lock)
    }

    deinit {
        self._lock.deinitialize(count: 1)
        self._lock.deallocate()
    }
}
