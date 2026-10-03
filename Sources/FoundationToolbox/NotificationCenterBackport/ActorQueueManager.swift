//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
//  Adapted from swift-foundation (https://github.com/swiftlang/swift-foundation),
//  Sources/FoundationEssentials/NotificationCenter/ActorQueueManager.swift at
//  3b9d8f4, distributed under the Apache License 2.0 with Runtime Library
//  Exception. See LICENSES/swift-foundation-LICENSE.
//
//  Modified for FrameworkToolbox: moved into `NotificationCenter.Backport`,
//  the worker loop no longer uses `withDiscardingTaskGroup` (see
//  `performWork(from:)`), and the manager is attached to its center as an
//  associated object rather than an instance variable.
//

import Foundation
import SwiftStdlibToolbox

extension NotificationCenter.Backport {
    // Runs the observers of `AsyncMessage`s: each delivered message becomes a
    // child task of one long-lived worker, so observers run concurrently, off
    // the posting thread, with none of the poster's task-local values.
    internal final class ActorQueueManager: @unchecked Sendable {
        struct State {
            var buffer = [@Sendable () async -> Void]()
            var continuation: UnsafeContinuation<(@Sendable () async -> Void)?, Never>?
            var isCancelled: Bool = false

            static func waitForWork(_ state: borrowing Mutex<State>) async -> (@Sendable () async -> Void)? {
                return await withTaskCancellationHandler {
                    return await withUnsafeContinuation { continuation in
                        let (work, resumeContinuation) = state.withLock { state -> ((@Sendable () async -> Void)?, Bool) in
                            if state.isCancelled {
                                return (nil, true)
                            } else {
                                if state.buffer.isEmpty {
                                    assert(state.continuation == nil)
                                    state.continuation = continuation
                                    return (nil, false)
                                } else {
                                    return (state.buffer.removeFirst(), true)
                                }
                            }
                        }
                        if resumeContinuation {
                            continuation.resume(returning: work)
                        }
                    }
                } onCancel: {
                    state.withLock { state in
                        state.isCancelled = true
                        defer {
                            state.continuation = nil
                        }
                        return state.continuation
                    }?.resume(returning: nil)
                }
            }
        }

        let stateReference: StateReference
        let workerTask: Task<(), Never>

        final class StateReference: Sendable {
            let state: Mutex<State>

            init(_ state: consuming Mutex<State>) {
                self.state = state
            }
        }

        init() {
            stateReference = StateReference(Mutex(State()))
            workerTask = Task.detached { [stateReference] in
                await ActorQueueManager.performWork(from: stateReference)
            }
        }

        deinit {
            workerTask.cancel()
        }

        func enqueue(_ work: @escaping @Sendable () async -> Void) {
            stateReference.state.withLock { state in
                state.buffer.append(work)
                if let continuation = state.continuation {
                    state.continuation = nil
                    let item = state.buffer.removeFirst()
                    continuation.resume(returning: item)
                }
            }
        }

        // What the worker's task group hears back from one of its children.
        enum WorkerEvent: Sendable {
            // The waiting child was handed the next piece of work.
            case workArrived(@Sendable () async -> Void)
            // A child finished running a piece of work.
            case workFinished
            // The waiting child was cancelled, so no further work will arrive.
            case waitingEnded
        }

        // Foundation's worker is
        //
        //     await withDiscardingTaskGroup { group in
        //         while let work = await State.waitForWork(stateRef.state) {
        //             group.addTask(operation: work)
        //         }
        //     }
        //
        // and `withDiscardingTaskGroup` needs macOS 14 / iOS 17. A plain task
        // group keeps every finished child until its result is taken, so a
        // long-lived center would accumulate one per delivered message. Taking
        // results means calling `next()`, which the loop cannot do while it is
        // also suspended in `waitForWork` — so waiting becomes a child task as
        // well, and the loop does nothing but `next()`: new work starts one
        // child to run it plus a fresh waiter, finished work is dropped. There
        // is never more than one waiter, which the `assert` in `waitForWork`
        // relies on. Cancelling the worker cancels every child, the waiter
        // included, and a cancelled waiter spawns no successor; the group then
        // drains and the loop ends, as Foundation's does when `waitForWork`
        // returns `nil`.
        //
        // This runs on every OS version rather than only below macOS 14 on
        // purpose. The older systems are what this port exists for, and
        // splitting on `#available` would make their branch the one the test
        // suite never executes.
        static func performWork(from stateReference: StateReference) async {
            await withTaskGroup(of: WorkerEvent.self) { group in
                group.addTask { await waitForNextWork(from: stateReference) }
                while let event = await group.next() {
                    guard case .workArrived(let work) = event else { continue }
                    group.addTask {
                        await work()
                        return .workFinished
                    }
                    group.addTask { await waitForNextWork(from: stateReference) }
                }
            }
        }

        private static func waitForNextWork(from stateReference: StateReference) async -> WorkerEvent {
            guard let work = await State.waitForWork(stateReference.state) else {
                return .waitingEnded
            }
            return .workArrived(work)
        }
    }
}

extension NotificationCenter.Backport.ActorQueueManager {
    // Foundation keeps the manager in an instance variable of the center,
    // creates it on first use under a lock, and releases it when the center
    // deallocates. An associated object has the same lifetime. The lock is not
    // optional: two managers created by a race would each start a worker, and
    // the one that lost the race would be released — cancelling its worker
    // with whatever work had already been enqueued on it.
    private static let attachmentLock = Mutex(())

    static func manager(attachedTo center: NotificationCenter) -> NotificationCenter.Backport.ActorQueueManager {
        if let manager = objc_getAssociatedObject(center, &actorQueueManagerAssociationKey) as? NotificationCenter.Backport.ActorQueueManager {
            return manager
        }
        return attachmentLock.withLock { _ in
            if let manager = objc_getAssociatedObject(center, &actorQueueManagerAssociationKey) as? NotificationCenter.Backport.ActorQueueManager {
                return manager
            }
            let manager = NotificationCenter.Backport.ActorQueueManager()
            objc_setAssociatedObject(center, &actorQueueManagerAssociationKey, manager, .OBJC_ASSOCIATION_RETAIN)
            return manager
        }
    }
}

private nonisolated(unsafe) var actorQueueManagerAssociationKey: UInt8 = 0
