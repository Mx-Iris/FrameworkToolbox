//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
//  Adapted from swift-foundation (https://github.com/swiftlang/swift-foundation),
//  Sources/FoundationEssentials/NotificationCenter/AsyncMessage+AsyncSequence.swift
//  at 3b9d8f4, distributed under the Apache License 2.0 with Runtime Library
//  Exception. See LICENSES/swift-foundation-LICENSE.
//
//  Modified for FrameworkToolbox: moved into `NotificationCenter.Backport`,
//  availability gates removed, the sequence and its iterator made public
//  because the opaque return type cannot be spelled below macOS 15, the
//  swift-collections `Deque` replaced by `MessageBuffer`, and only the Darwin
//  (`FOUNDATION_FRAMEWORK`) observer kept.
//

import Foundation
import SwiftStdlibToolbox

extension NotificationCenter {
    /// Returns an asynchronous sequence of messages produced by this center for a given subject and identifier.
    /// - Parameters:
    ///   - subject: The subject to observe. Specify a metatype to observe all values for a given type.
    ///   - identifier: An identifier representing a specific message type.
    ///   - limit: The maximum number of messages allowed to buffer.
    /// - Returns: An asynchronous sequence of messages produced by this center.
    public func messages<Identifier: Backport.MessageIdentifier, Message: Backport.AsyncMessage>(
        of subject: Message.Subject,
        for identifier: Identifier,
        bufferSize limit: Int = 10
    ) -> Backport.AsyncMessageSequence<Message> where Identifier.MessageType == Message, Message.Subject: AnyObject {
        return Backport.AsyncMessageSequence<Message>(self, subject, limit)
    }

    /// Returns an asynchronous sequence of messages produced by this center for a given subject type and identifier.
    /// - Parameters:
    ///   - subject: The metatype to observe all values for a given type.
    ///   - identifier: An identifier representing a specific message type.
    ///   - limit: The maximum number of messages allowed to buffer.
    /// - Returns: An asynchronous sequence of messages produced by this center.
    public func messages<Identifier: Backport.MessageIdentifier, Message: Backport.AsyncMessage>(
        of subject: Message.Subject.Type,
        for identifier: Identifier,
        bufferSize limit: Int = 10
    ) -> Backport.AsyncMessageSequence<Message> where Identifier.MessageType == Message {
        return Backport.AsyncMessageSequence<Message>(self, nil, limit)
    }

    /// Returns an asynchronous sequence of messages produced by this center for a given subject and message type.
    /// - Parameters:
    ///   - subject: The subject to observe. Specify a metatype to observe all values for a given type.
    ///   - messageType: The message type to be observed.
    ///   - limit: The maximum number of messages allowed to buffer.
    /// - Returns: An asynchronous sequence of messages produced by this center.
    public func messages<Message: Backport.AsyncMessage>(
        of subject: Message.Subject? = nil,
        for messageType: Message.Type,
        bufferSize limit: Int = 10
    ) -> Backport.AsyncMessageSequence<Message> where Message.Subject: AnyObject {
        return Backport.AsyncMessageSequence<Message>(self, subject, limit)
    }
}

extension NotificationCenter.Backport {
    /// The asynchronous sequence of messages that `messages(of:for:bufferSize:)` returns.
    ///
    /// Foundation's `messages(of:for:bufferSize:)` returns `some AsyncSequence<Message, Never> & Sendable` and keeps this
    /// type private. That spelling names `AsyncSequence`'s `Failure` associated type, which exists only from macOS 15,
    /// iOS 18, tvOS 18, watchOS 11 and visionOS 2, so here the type itself is public instead. Iterate it the same way;
    /// where `Failure` exists it is inferred as `Never`, so the sequence can be passed wherever
    /// `some AsyncSequence<Message, Never>` is expected.
    ///
    /// Observation begins in `makeAsyncIterator()`, not when the sequence is created: each iterator registers its own
    /// observer and buffers up to the requested number of messages, dropping the oldest one when a new message arrives
    /// at a full buffer. Copies of one iterator share its buffer. The sequence holds its subject weakly; if the subject
    /// is gone by the time an iterator is made, that iterator observes every subject.
    public struct AsyncMessageSequence<Message: AsyncMessage>: AsyncSequence, Sendable {
        public typealias Element = Message

        let center: NotificationCenter
        nonisolated(unsafe) weak var object: AnyObject?
        let bufferSize: Int

        init(_ center: NotificationCenter, _ object: AnyObject?, _ bufferSize: Int) {
            self.center = center
            self.object = object
            self.bufferSize = bufferSize
        }

        public func makeAsyncIterator() -> Iterator {
            return Iterator(storage: AsyncMessageSequenceIterator(center: center, object: object, bufferSize: bufferSize))
        }

        /// The iterator of an ``NotificationCenter/Backport/AsyncMessageSequence``.
        ///
        /// Copies share one observation and one buffer, as in Foundation, where the iterator is a class. It is a
        /// struct over that class here — the shape of `AsyncStream.Iterator` — so that `next()` is `mutating` and an
        /// iterator is declared with `var`, exactly as Foundation's opaque one must be. Observation ends when the last
        /// copy is released, or when the task waiting in `next()` is cancelled; `next()` returns `nil` from then on.
        public struct Iterator: AsyncIteratorProtocol, Sendable {
            public typealias Element = Message

            let storage: AsyncMessageSequenceIterator<Message>

            public mutating func next() async -> Message? {
                await storage.next()
            }
        }
    }
}

extension NotificationCenter.Backport {
    // Foundation's iterator, under its upstream name. `AsyncMessageSequence.Iterator` is the public face of it.
    final class AsyncMessageSequenceIterator<Message: AsyncMessage>: Sendable {
        struct State {
            var observer: NotificationCenter.Backport.ObservationToken?
            var continuations: [UnsafeContinuation<Message?, Never>] = []
            var buffer = NotificationCenter.Backport.MessageBuffer<Message>(minimumCapacity: 1)
            let bufferSize: Int
        }

        struct Resumption {
            let message: Message?
            let continuations: [UnsafeContinuation<Message?, Never>]

            init(message: Message?, continuation: UnsafeContinuation<Message?, Never>) {
                self.message = message
                self.continuations = [continuation]
            }

            init(cancelling: [UnsafeContinuation<Message?, Never>]) {
                self.message = nil
                self.continuations = cancelling
            }

            func resume() {
                for continuation in continuations {
                    continuation.resume(returning: message)
                }
            }
        }

        let state: Mutex<State>

        init(center: NotificationCenter, object: AnyObject?, bufferSize: Int) {
            self.state = Mutex(State(bufferSize: bufferSize))

            let observerBlock: @Sendable (Notification) -> Void = { [weak self] notification in
                guard let message: Message = NotificationCenter._messageFromNotification(notification) else { return }

                self?.observationCallback(message)
            }

            let token = center._addObserver(Message.name, object: object, using: observerBlock)

            self.state.withLock { _state in
                _state.observer = NotificationCenter.Backport.ObservationToken(center: center, token: token)
            }
        }

        deinit {
            teardown()
        }

        func teardown() {
            let (observer, resumption) = state.withLock { _state -> (NotificationCenter.Backport.ObservationToken?, Resumption) in
                let observer = _state.observer
                _state.observer = nil
                _state.buffer.removeAll(keepingCapacity: false)
                defer { _state.continuations.removeAll(keepingCapacity: false) }
                return (observer, Resumption(cancelling: _state.continuations))
            }

            resumption.resume()

            if let observer {
                observer.remove()
            }
        }

        func observationCallback(_ message: Message) {
            state.withLock { _state -> Resumption? in
                if _state.buffer.count + 1 > _state.bufferSize {
                    _state.buffer.removeFirst()
                    NotificationCenterBackportDiagnostics.reportDroppedMessage(messageType: Message.self)
                }
                _state.buffer.append(message)

                if _state.continuations.isEmpty {
                    return nil
                } else {
                    return Resumption(message: _state.buffer.removeFirst(), continuation: _state.continuations.removeFirst())
                }
            }?.resume()
        }

        func next() async -> Message? {
            await withTaskCancellationHandler {
                return await withUnsafeContinuation { (continuation: UnsafeContinuation<Message?, Never>) in
                    state.withLock { _state -> Resumption? in
                        _state.continuations.append(continuation)
                        if _state.buffer.isEmpty {
                            return nil
                        } else {
                            return Resumption(message: _state.buffer.removeFirst(), continuation: _state.continuations.removeFirst())
                        }
                    }?.resume()
                }
            } onCancel: {
                teardown()
            }
        }
    }
}
