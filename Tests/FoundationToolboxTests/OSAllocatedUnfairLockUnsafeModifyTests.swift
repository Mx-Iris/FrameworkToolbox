#if OSAllocatedUnfairLockUnsafeModify

import Testing
import os
@testable import FoundationToolbox

// Runtime verification for the `_unsafeLock` / `_unsafeUnlock` extension, which
// bit-casts `OSAllocatedUnfairLock<State>` to its internal
// `ManagedBuffer<State, os_unfair_lock>` to yield a pointer into the protected
// storage. If Apple's @frozen layout ever changes, these tests catch it.
@Suite
struct OSAllocatedUnfairLockUnsafeModifyTests {

    @Test func unsafeLockExposesLivePointer() throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        let lock = OSAllocatedUnfairLock<Int>(initialState: 41)

        let pointer = lock._unsafeLock()
        #expect(pointer.pointee == 41)
        pointer.pointee += 1
        lock._unsafeUnlock()

        #expect(lock.withLock { $0 } == 42)
    }

    @Test func unsafeModifyPairingSerialisesConcurrentWriters() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        let lock = OSAllocatedUnfairLock<Int>(initialState: 0)
        let iterations = 1_000
        let writers = 8

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<writers {
                group.addTask {
                    for _ in 0..<iterations {
                        let pointer = lock._unsafeLock()
                        pointer.pointee += 1
                        lock._unsafeUnlock()
                    }
                }
            }
        }

        #expect(lock.withLock { $0 } == writers * iterations)
    }

    @Test func unsafeModifyMutatesReferenceTypeInPlace() throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        let lock = OSAllocatedUnfairLock<[String]>(initialState: [])

        let pointer = lock._unsafeLock()
        pointer.pointee.append("a")
        pointer.pointee.append("b")
        lock._unsafeUnlock()

        #expect(lock.withLock { $0 } == ["a", "b"])
    }
}

#endif
