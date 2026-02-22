import os

@frozen
public struct Mutex<Value: ~Copyable>: ~Copyable, @unchecked Sendable {
    @usableFromInline
    internal let _buffer: UnsafeMutableRawPointer

    // MARK: - Memory Layout

    /// Byte offset from buffer start to the Value storage.
    /// Layout: [os_unfair_lock | padding | Value]
    @usableFromInline
    internal static var _valueOffset: Int {
        let lockSize = MemoryLayout<os_unfair_lock>.size
        let valueAlignment = max(MemoryLayout<Value>.alignment, 1)
        // Round up lockSize to the nearest multiple of valueAlignment
        return (lockSize + valueAlignment - 1) & ~(valueAlignment - 1)
    }

    @usableFromInline
    internal var _lockPtr: UnsafeMutablePointer<os_unfair_lock> {
        _buffer.assumingMemoryBound(to: os_unfair_lock.self)
    }

    @usableFromInline
    internal var _valuePtr: UnsafeMutablePointer<Value> {
        _buffer.advanced(by: Self._valueOffset)
              .assumingMemoryBound(to: Value.self)
    }

    // MARK: - Lifecycle

    @inlinable
    public init(_ initialValue: consuming sending Value) {
        let valueOffset = Self._valueOffset
        let totalSize = valueOffset + MemoryLayout<Value>.size
        let alignment = max(
            MemoryLayout<os_unfair_lock>.alignment,
            MemoryLayout<Value>.alignment
        )

        // Single allocation for both lock and value
        _buffer = .allocate(
            byteCount: max(totalSize, 1),
            alignment: max(alignment, 1)
        )

        // Initialize lock region
        _buffer
            .bindMemory(to: os_unfair_lock.self, capacity: 1)
            .initialize(to: os_unfair_lock())

        // Initialize value region (non-overlapping, different type binding is valid)
        _buffer
            .advanced(by: valueOffset)
            .bindMemory(to: Value.self, capacity: 1)
            .initialize(to: initialValue)
    }

    @inlinable
    deinit {
        // Deinitialize value (runs destructors / releases references)
        // Lock is trivial (UInt32), no deinit needed
        _valuePtr.deinitialize(count: 1)
        _buffer.deallocate()
    }

    // MARK: - Locking API

    @inlinable
    public borrowing func withLock<Result: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending Result
    ) throws(E) -> sending Result {
        os_unfair_lock_lock(_lockPtr)
        defer { os_unfair_lock_unlock(_lockPtr) }
        return try body(&_valuePtr.pointee)
    }

    @inlinable
    public borrowing func withLockIfAvailable<Result: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending Result
    ) throws(E) -> sending Result? {
        guard os_unfair_lock_trylock(_lockPtr) else { return nil }
        defer { os_unfair_lock_unlock(_lockPtr) }
        return try body(&_valuePtr.pointee)
    }

    /// Variant without `sending` constraint on the closure parameter.
    /// Use when you already know you're in the correct isolation domain.
    @inlinable
    public borrowing func withLockUnchecked<Result: ~Copyable, E: Error>(
        _ body: (inout Value) throws(E) -> Result
    ) throws(E) -> Result {
        os_unfair_lock_lock(_lockPtr)
        defer { os_unfair_lock_unlock(_lockPtr) }
        return try body(&_valuePtr.pointee)
    }
}
