import Testing
import Dispatch
@testable import SwiftStdlibToolbox

// MARK: - LockSingleConsumerStack (ported from swift/test/stdlib/Synchronization/Mutex)

/// A concurrent stack that allows arbitrary concurrent pushes but only a single
/// consumer at a time. Used to exercise Mutex under realistic contention.
private class LockSingleConsumerStack<Element> {
    struct Node {
        let value: Element
        var next: UnsafeMutablePointer<Node>?
    }
    typealias NodePtr = UnsafeMutablePointer<Node>

    private let _last = Mutex<NodePtr?>(nil)
    private let _consumerCount = Mutex<Int>(0)

    deinit {
        while let _ = pop() {}
    }

    func push(_ value: Element) {
        let new = NodePtr.allocate(capacity: 1)
        new.initialize(to: Node(value: value, next: nil))

        _last.withLock {
            new.pointee.next = $0
            $0 = new
        }
    }

    func pop() -> Element? {
        precondition(
            _consumerCount.withLock {
                let old = $0
                $0 += 1
                return old == 0
            },
            "Multiple consumers detected")

        defer {
            _consumerCount.withLock { $0 -= 1 }
        }

        return _last.withLock { (c: inout NodePtr?) -> Element? in
            guard let current = c else { return nil }
            c = current.pointee.next
            let result = current.move()
            current.deallocate()
            return result.value
        }
    }
}

@Suite("Mutex")
struct MutexTests {

    // MARK: - Basic Value Access

    @Test("withLock reads initial value")
    func readInitialValue() {
        let mutex = Mutex(42)
        let value = mutex.withLock { $0 }
        #expect(value == 42)
    }

    @Test("withLock mutates value")
    func mutateValue() {
        let mutex = Mutex(0)
        mutex.withLock { $0 = 99 }
        let value = mutex.withLock { $0 }
        #expect(value == 99)
    }

    @Test("withLock returns transformed result")
    func returnTransformedResult() {
        let mutex = Mutex([1, 2, 3])
        let sum = mutex.withLock { $0.reduce(0, +) }
        #expect(sum == 6)
    }

    // MARK: - withLockIfAvailable

    @Test("withLockIfAvailable succeeds when lock is free")
    func lockIfAvailableSucceeds() {
        let mutex = Mutex(10)
        let result = mutex.withLockIfAvailable { $0 }
        #expect(result == 10)
    }

    @Test("withLockIfAvailable mutates value")
    func lockIfAvailableMutates() {
        let mutex = Mutex("hello")
        mutex.withLockIfAvailable { $0 = "world" }
        let value = mutex.withLock { $0 }
        #expect(value == "world")
    }

    // MARK: - withLockUnchecked

    @Test("withLockUnchecked reads value")
    func lockUncheckedReads() {
        let mutex = Mutex(3.14)
        let value = mutex.withLockUnchecked { $0 }
        #expect(value == 3.14)
    }

    @Test("withLockUnchecked mutates value")
    func lockUncheckedMutates() {
        let mutex = Mutex([Int]())
        mutex.withLockUnchecked { $0.append(1) }
        mutex.withLockUnchecked { $0.append(2) }
        let value = mutex.withLockUnchecked { $0 }
        #expect(value == [1, 2])
    }

    // MARK: - Error Propagation

    @Test("withLock propagates thrown error")
    func withLockPropagatesError() {
        struct TestError: Error {}
        let mutex = Mutex(0)
        #expect(throws: TestError.self) {
            try mutex.withLock { _ -> Int in throw TestError() }
        }
    }

    @Test("withLockIfAvailable propagates thrown error")
    func withLockIfAvailablePropagatesError() {
        struct TestError: Error {}
        let mutex = Mutex(0)
        #expect(throws: TestError.self) {
            try mutex.withLockIfAvailable { _ -> Int in throw TestError() }
        }
    }

    @Test("withLockUnchecked propagates thrown error")
    func withLockUncheckedPropagatesError() {
        struct TestError: Error {}
        let mutex = Mutex(0)
        #expect(throws: TestError.self) {
            try mutex.withLockUnchecked { _ -> Int in throw TestError() }
        }
    }

    @Test("value is unchanged after throwing")
    func valueUnchangedAfterThrow() {
        struct TestError: Error {}
        let mutex = Mutex(42)
        _ = try? mutex.withLock { _ -> Int in throw TestError() }
        let value = mutex.withLock { $0 }
        #expect(value == 42)
    }

    // MARK: - Various Value Types

    @Test("works with String value")
    func stringValue() {
        let mutex = Mutex("swift")
        mutex.withLock { $0 = $0.uppercased() }
        #expect(mutex.withLock { $0 } == "SWIFT")
    }

    @Test("works with Optional value")
    func optionalValue() {
        let mutex = Mutex<Int?>(nil)
        mutex.withLock { $0 = 42 }
        #expect(mutex.withLock { $0 } == 42)
    }

    @Test("works with reference type value")
    func referenceTypeValue() {
        final class Box { var value: Int; init(_ v: Int) { value = v } }
        let mutex = Mutex(Box(1))
        mutex.withLock { $0.value = 100 }
        let result = mutex.withLock { $0.value }
        #expect(result == 100)
    }

    @Test("works with empty tuple (Void)")
    func voidValue() {
        let mutex = Mutex(())
        mutex.withLock { _ in }
    }

    // MARK: - Concurrent Access

    @Test("concurrent increments produce correct total")
    func concurrentIncrements() async {
        let mutex = Mutex(0)
        let iterations = 1000

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask { mutex.withLock { $0 += 1 } }
            }
        }

        let value = mutex.withLock { $0 }
        #expect(value == iterations)
    }

    @Test("concurrent reads and writes do not corrupt data")
    func concurrentReadsAndWrites() async {
        let mutex = Mutex([Int]())
        let count = 500

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<count {
                group.addTask { mutex.withLock { $0.append(i) } }
            }
        }

        let result = mutex.withLock { $0 }
        #expect(result.count == count)
        #expect(Set(result) == Set(0..<count))
    }

    @Test("withLockUnchecked works under concurrent access")
    func concurrentUnchecked() async {
        let mutex = Mutex(0)
        let iterations = 1000

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask { mutex.withLockUnchecked { $0 += 1 } }
            }
        }

        let value = mutex.withLockUnchecked { $0 }
        #expect(value == iterations)
    }

    // MARK: - LockSingleConsumerStack (from Swift stdlib)

    @Test("stack basics: push and pop ordering")
    func stackBasics() {
        let stack = LockSingleConsumerStack<Int>()
        #expect(stack.pop() == nil)
        stack.push(0)
        #expect(stack.pop() == 0)

        stack.push(1)
        stack.push(2)
        stack.push(3)
        stack.push(4)
        #expect(stack.pop() == 4)
        #expect(stack.pop() == 3)
        #expect(stack.pop() == 2)
        #expect(stack.pop() == 1)
        #expect(stack.pop() == nil)
    }

    @Test("stack concurrent pushes preserve all values")
    func stackConcurrentPushes() {
        let stack = LockSingleConsumerStack<(thread: Int, value: Int)>()

        let numThreads = 100
        let numValues = 10_000
        DispatchQueue.concurrentPerform(iterations: numThreads) { thread in
            for value in 1...numValues {
                stack.push((thread: thread, value: value))
            }
        }

        var expected = Array(repeating: numValues, count: numThreads)
        while let (thread, value) = stack.pop() {
            #expect(expected[thread] == value)
            expected[thread] -= 1
        }
        #expect(expected == Array(repeating: 0, count: numThreads))
    }

    @Test("stack concurrent pushes and pops")
    func stackConcurrentPushesAndPops() {
        let stack = LockSingleConsumerStack<(thread: Int, value: Int)>()

        let numThreads = 100
        let numValues = 10_000

        var perThreadSums = Array(repeating: 0, count: numThreads)
        let consumerQueue = DispatchQueue(label: "org.swift.test.consumer")
        consumerQueue.async {
            var count = 0
            while count < numThreads * numValues {
                if let (thread, value) = stack.pop() {
                    perThreadSums[thread] += value
                    count += 1
                }
            }
        }

        DispatchQueue.concurrentPerform(iterations: numThreads) { thread in
            for value in 0..<numValues {
                stack.push((thread: thread, value: value))
            }
        }

        consumerQueue.sync {
            let expectedSum = numValues * (numValues - 1) / 2
            #expect(perThreadSums == Array(repeating: expectedSum, count: numThreads))
        }
    }
}
