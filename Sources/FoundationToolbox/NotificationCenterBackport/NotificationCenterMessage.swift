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
//  Sources/FoundationEssentials/NotificationCenter/NotificationCenterMessage.swift
//  at 3b9d8f4, distributed under the Apache License 2.0 with Runtime Library
//  Exception. See LICENSES/swift-foundation-LICENSE.
//
//  Modified for FrameworkToolbox: moved into `NotificationCenter.Backport`,
//  availability gates removed, the token wrapper now holds an observer object
//  behind a lock instead of an integer, and the actor queue manager is
//  attached to the center as an associated object instead of an ivar.
//

import Foundation
import SwiftStdlibToolbox

extension NotificationCenter.Backport {
    /// An optional identifier to associate a given message with a given type.
    ///
    /// Implement a `MessageIdentifier` to provide a typed, ergonomic experience at the call point, as described in [SE-0299](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0299-extend-generic-static-member-lookup.md).
    ///
    /// For example, given `ExampleMessage` with a `Subject` called `ExampleSubject`:
    ///
    /// ```swift
    /// extension NotificationCenter.Backport.MessageIdentifier where Self == NotificationCenter.Backport.BaseMessageIdentifier<ExampleMessage> {
    ///     static var eventDidOccur: Self { .init() }
    /// }
    /// ```
    ///
    /// This simplifies the call point for clients, as seen here:
    ///
    /// ```swift
    /// let token = center.addObserver(of: exampleSubject, for: .eventDidOccur) { ... }
    /// ```
    public protocol MessageIdentifier {
        associatedtype MessageType
    }

    /// A type for use when defining optional Message identifiers.
    ///
    /// See ``MessageIdentifier`` for an example of how to use this type when defining your own message identifiers.
    public struct BaseMessageIdentifier<MessageType>: MessageIdentifier, Sendable {
        public init() where MessageType: MainActorMessage {}
        public init() where MessageType: AsyncMessage {}
    }
}

extension NotificationCenter.Backport {
    /// A unique token representing a single observer registration in a notification center.
    ///
    /// You receive the `ObservationToken` type as a return value from `addObserver(of:for:using:)` and related methods.
    ///
    /// Retain the `ObservationToken` for as long as you need to continue observation, since observation ends when the token goes out of scope.
    /// You can also explicitly stop observing by passing the token to `NotificationCenter.removeObserver(_:)`.
    public struct ObservationToken: Hashable, Sendable {
        private let tokenWrapper: NotificationObserverTokenWrapper
        internal var center: NotificationCenter? { self.tokenWrapper.center }

        internal init(center: NotificationCenter, token: NotificationObserverToken) {
            self.tokenWrapper = NotificationObserverTokenWrapper(center: center, token: token)
        }

        internal func remove() {
            self.tokenWrapper.remove()
        }

        fileprivate final class NotificationObserverTokenWrapper: Hashable, @unchecked Sendable {
            // Foundation's token is an integer, so two threads removing one
            // registration at once is a benign race there: CoreFoundation
            // ignores a token it has already cancelled. Here the token is an
            // object reference, and the same race would be concurrent writes to
            // one strong reference, which can over-release it — hence the lock.
            private let token: Mutex<NotificationObserverToken?>
            fileprivate weak var center: NotificationCenter?

            init(center: NotificationCenter, token: NotificationObserverToken) {
                self.token = Mutex(token)
                self.center = center
            }

            func remove() {
                if let value = token.withLock({ $0.take() }) {
                    self.center?._removeObserver(value)
                }
            }

            deinit {
                self.remove()
            }

            // Compares what the token currently holds, as Foundation's does —
            // so once removed, a token equals every other removed token and
            // hashes differently than it did while active.
            static func == (lhs: NotificationObserverTokenWrapper, rhs: NotificationObserverTokenWrapper) -> Bool {
                return lhs.currentToken === rhs.currentToken
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(currentToken.map(ObjectIdentifier.init))
            }

            private var currentToken: NotificationObserverToken? {
                token.withLock { $0 }
            }
        }
    }
}

extension NotificationCenter {
    /// Stops the observation represented by the given observation token.
    ///
    /// - Parameter token: a unique token representing a specific observer in a specific notification center. You receive this type from prior calls to `addObserver(of:for:using:)`.
    public func removeObserver(_ token: Backport.ObservationToken) {
        // Read once: the center is held weakly and could go away between two reads.
        let tokenCenter = token.center
        guard tokenCenter == nil || tokenCenter == self else {
            NotificationCenterBackportDiagnostics.reportTokenFromAnotherCenter(tokenCenter: tokenCenter!, receivingCenter: self)
            return
        }

        token.remove()
    }
}

extension NotificationCenter.Backport {
    // The `userInfo` key a posted message travels under, so that an observer of
    // the same message type gets the original value back rather than one rebuilt
    // by `makeMessage(_:)`. An instance of a private class, so no key a caller
    // writes can collide with it.
    internal final class NotificationMessageKey: NSObject, NSCopying, Sendable {
        func copy(with zone: NSZone? = nil) -> Any { return self }

        static let key = NotificationMessageKey()
    }
}

extension NotificationCenter {
    internal var asyncObserverQueue: Backport.ActorQueueManager {
        Backport.ActorQueueManager.manager(attachedTo: self)
    }
}
