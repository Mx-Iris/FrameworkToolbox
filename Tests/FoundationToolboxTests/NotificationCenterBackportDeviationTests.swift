@testable import FoundationToolbox
import Foundation
import Testing

// Covers what `NotificationCenterBackportTests.swift` cannot, because it is a
// port of upstream's suite: the places where this copy has to work differently
// from Foundation's, and the Foundation behaviors it deliberately keeps. Each
// group names the decision it pins; the reasons are in the
// `notification-center-backport` proposal.
@Suite("NotificationCenterBackport deviations", notificationCenterBackportTimeLimit)
private struct NotificationCenterBackportDeviationTests {

    // MARK: - Registration does not keep the center alive

    // Foundation's private registration retains neither the observer nor the
    // center; the block-based public API would retain the center until removal.
    @MainActor
    @Test func mainActorObservationDoesNotRetainItsCenter() {
        weak var weakCenter: NotificationCenter?
        var token: NotificationCenter.Backport.ObservationToken?

        autoreleasepool {
            let center = NotificationCenter()
            weakCenter = center
            token = center.addObserver(of: MessageTestSubject.self, for: .messagePosted) { _ in }
        }

        #expect(weakCenter == nil)
        withExtendedLifetime(token) {}
    }

    @Test func messageSequenceIteratorDoesNotRetainItsCenter() {
        weak var weakCenter: NotificationCenter?
        var iterator: NotificationCenter.Backport.AsyncMessageSequence<AsyncTestMessage>.Iterator?

        autoreleasepool {
            let center = NotificationCenter()
            weakCenter = center
            iterator = center.messages(for: AsyncTestMessage.self).makeAsyncIterator()
        }

        #expect(weakCenter == nil)
        withExtendedLifetime(iterator) {}
    }

    // MARK: - The actor queue manager lives and dies with its center

    // Foundation releases the manager in the center's `dealloc`, which cancels
    // the worker. Here the manager is an associated object, and the worker loop
    // is not Foundation's: it has to wind down once cancelled, or this hangs.
    @Test func actorQueueManagerIsReleasedWithItsCenterAndItsWorkerFinishes() async {
        weak var weakManager: NotificationCenter.Backport.ActorQueueManager?
        var workerTask: Task<(), Never>?

        autoreleasepool {
            let center = NotificationCenter()
            let manager = center.asyncObserverQueue
            #expect(center.asyncObserverQueue === manager)
            weakManager = manager
            workerTask = manager.workerTask
        }

        #expect(weakManager == nil)
        if let workerTask {
            #expect(await waitForCompletion(of: workerTask, timeoutSeconds: 10), "the worker should end once its manager is released")
        }
    }

    // MARK: - The worker loop without `withDiscardingTaskGroup`

    // Each delivery hands the work from a waiting child back to the loop, which
    // then starts the next waiter. A burst exercises that hand-off far more often
    // than any upstream test does.
    @Test func asyncObserverReceivesEveryMessageOfABurst() async {
        let center = NotificationCenter()
        let messageCount = 1_000
        let counter = SynchronizedCounter()
        var token: NotificationCenter.Backport.ObservationToken?

        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            token = center.addObserver(for: AsyncTestMessage.self) { _ in
                if counter.increment() == messageCount { continuation.resume() }
            }
            for payload in 1...messageCount {
                center.post(AsyncTestMessage(payloadInt: payload, payloadString: "N/A"))
            }
        }

        withExtendedLifetime(token) {}
    }

    // MARK: - `MessageBuffer` stands in for `Deque`

    @Test func messageBufferIsFirstInFirstOutAcrossCompaction() {
        var buffer = NotificationCenter.Backport.MessageBuffer<Int>(minimumCapacity: 1)
        #expect(buffer.isEmpty)

        buffer.appendAll(0..<100)
        #expect(buffer.count == 100)

        // Removing past the halfway point discards the consumed prefix.
        #expect(buffer.removeFirst(60) == Array(0..<60))
        #expect(buffer.count == 40)

        buffer.appendAll(100..<150)
        #expect(buffer.removeFirst(90) == Array(60..<150))
        #expect(buffer.isEmpty)
    }

    @Test func messageBufferStaysOrderedWhenAlternatingAppendAndRemove() {
        var buffer = NotificationCenter.Backport.MessageBuffer<Int>(minimumCapacity: 1)
        var removed: [Int] = []

        for value in 0..<1_000 {
            buffer.append(value)
            if value.isMultiple(of: 3) == false {
                removed.append(buffer.removeFirst())
            }
        }
        removed.append(contentsOf: buffer.removeFirst(buffer.count))

        #expect(removed == Array(0..<1_000))
    }

    @Test func messageBufferRemoveAllEmptiesIt() {
        var buffer = NotificationCenter.Backport.MessageBuffer<String>(minimumCapacity: 1)
        buffer.appendAll(["first", "second", "third"])
        _ = buffer.removeFirst()

        buffer.removeAll(keepingCapacity: false)

        #expect(buffer.isEmpty)
        buffer.append("fourth")
        #expect(buffer.removeFirst() == "fourth")
    }

    // MARK: - `messages(of:for:)` returns a named type

    // Foundation returns `some AsyncSequence<Message, Never>`. Where that spelling
    // exists, the named type has to fit it — `Failure` inferred as `Never`.
    @Test func messageSequenceIsAnAsyncSequenceThatNeverThrowsWhereFailureExists() async {
        guard #available(SwiftStdlib 6.0, *) else { return }

        let center = NotificationCenter()
        let message = await firstMessage(of: center.messages(for: AsyncTestMessage.self)) {
            center.post(AsyncTestMessage(payloadInt: 7, payloadString: "seven"))
        }

        #expect(message?.payloadInt == 7)
    }

    // MARK: - Removing a token is safe from many threads at once

    // Foundation's integer token makes a concurrent removal benign; with an
    // object reference it would race on one strong reference. The lock has to
    // let exactly one of the callers through. Without the lock a single round
    // still passes about nine times in ten, and twenty rounds passed one run in
    // five, so this runs a hundred.
    @Test func concurrentRemovalOfOneTokenRemovesItOnce() async {
        let center = RegistrationCountingNotificationCenter()

        for _ in 0..<100 {
            let token = center.addObserver(for: AsyncTestMessage.self) { _ in }
            #expect(center.registrationCount == 1)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<64 {
                    group.addTask { center.removeObserver(token) }
                }
            }

            #expect(center.registrationCount == 0)
        }
    }

    // MARK: - Foundation behavior kept as is

    // Equality compares what a token currently holds, as Foundation's does: a
    // removed token equals every other removed token, and its hash changes.
    @MainActor
    @Test func removedTokensCompareEqualAsInFoundation() {
        let center = NotificationCenter()
        let first = center.addObserver(for: MainActorTestMessage.self) { _ in }
        let second = center.addObserver(for: MainActorTestMessage.self) { _ in }
        #expect(first != second)

        center.removeObserver(first)
        center.removeObserver(second)

        #expect(first == second)
    }
}

// Waits for `task` to finish, giving up after `timeoutSeconds`, and reports
// which happened first. The race is unstructured on purpose: awaiting a task's
// value ignores cancellation, so a task group racing it against a sleep would
// itself wait for the very hang it is meant to report — and so would a time
// limit trait, which only cancels the test.
private func waitForCompletion(of task: Task<(), Never>, timeoutSeconds: UInt64) async -> Bool {
    let outcome = FirstOutcome()
    var timeoutTask: Task<Void, Never>?
    let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        outcome.install(continuation)
        Task {
            await task.value
            outcome.resolve(true)
        }
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            outcome.resolve(false)
        }
    }
    timeoutTask?.cancel()
    return finished
}

// Resumes a continuation with whichever outcome arrives first.
private final class FirstOutcome: Sendable {
    private let continuation = Mutex<CheckedContinuation<Bool, Never>?>(nil)

    func install(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation.withLock { $0 = continuation }
    }

    func resolve(_ outcome: Bool) {
        continuation.withLock { $0.take() }?.resume(returning: outcome)
    }
}

// Takes the sequence the way Foundation's `messages(of:for:bufferSize:)` hands
// it out. Observation starts in `makeAsyncIterator()`, so posting happens
// between that and `next`.
@available(SwiftStdlib 6.0, *)
private func firstMessage<Message>(
    of sequence: some AsyncSequence<Message, Never>,
    afterPosting post: () -> Void
) async -> Message? {
    var iterator = sequence.makeAsyncIterator()
    post()
    return await iterator.next(isolation: nil)
}

extension NotificationCenter.Backport.MessageBuffer {
    fileprivate mutating func appendAll(_ elements: some Sequence<Element>) {
        for element in elements {
            append(element)
        }
    }

    fileprivate mutating func removeFirst(_ elementCount: Int) -> [Element] {
        (0..<elementCount).map { _ in removeFirst() }
    }
}
