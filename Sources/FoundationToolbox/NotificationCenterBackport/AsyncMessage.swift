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
//  Sources/FoundationEssentials/NotificationCenter/AsyncMessage.swift at
//  3b9d8f4, distributed under the Apache License 2.0 with Runtime Library
//  Exception. See LICENSES/swift-foundation-LICENSE.
//
//  Modified for FrameworkToolbox: moved into `NotificationCenter.Backport`,
//  availability gates removed, only the Darwin (`FOUNDATION_FRAMEWORK`)
//  implementation kept, and its private observer registration replaced (see
//  `NotificationCenterBackport.swift`).
//

import Foundation
import SwiftStdlibToolbox

extension NotificationCenter.Backport {
    /// A protocol for creating types that you can post to a notification center, which posts them to an arbitrary isolation.
    ///
    /// You post types conforming to `AsyncMessage` to a notification center using `post(_:subject:)` and observe them with `addObserver(of:for:using:)`.
    ///
    /// The notification center delivers `AsyncMessage` types asynchronously when posted. Asynchronous delivery isn't suitable
    /// for messages with time-critical deliveries, such as a message that must have its observers called before a certain
    /// action takes place.
    ///
    /// For types that post on the main actor, use ``MainActorMessage``.
    ///
    /// Each `AsyncMessage` is associated with a specific `Subject` type.
    ///
    /// For example, an `AsyncMessage` associated with the type `Event` could use the following declaration:
    ///
    /// ```swift
    /// struct EventDidStart: NotificationCenter.Backport.AsyncMessage {
    ///     typealias Subject = Event
    /// }
    /// ```
    ///
    /// `AsyncMessage` can use an optional ``MessageIdentifier`` type for context-aware observer registration:
    ///
    /// ```swift
    /// extension NotificationCenter.Backport.MessageIdentifier where Self == NotificationCenter.Backport.BaseMessageIdentifier<EventDidStart> {
    ///     static var didStart: Self { .init() }
    /// }
    /// ```
    ///
    /// With this identifier, observers can receive information about a specific instance by registering for this message with a `NotificationCenter`:
    ///
    /// ```swift
    /// let observerToken = NotificationCenter.default.addObserver(of: importantEvent, for: .didStart)
    /// ```
    ///
    /// Or an observer can receive information about any instance with:
    ///
    /// ```swift
    /// let observerToken = NotificationCenter.default.addObserver(of: Event.self, for: .didStart)
    /// ```
    ///
    /// The notification center ties observation to the lifetime of the returned ``ObservationToken`` and automatically de-registers the observer if the token
    /// goes out of scope. You can also remove observation explicitly:
    ///
    /// ```swift
    /// NotificationCenter.default.removeObserver(observerToken)
    /// ```
    ///
    /// ### Notification Interoperability
    ///
    /// `AsyncMessage` includes optional interoperability with `Notification`, enabling posters and observers of both types
    /// to pass information.
    ///
    /// It does this by offering a ``makeMessage(_:)`` method that collects values from a `Notification`'s `userInfo` and populates properties on a new message.
    /// In the other direction, a ``makeNotification(_:)`` method collects the message's defined properties and loads them into a new notification's `userInfo` dictionary.
    ///
    /// For example, if there exists a `Notification` posted on an arbitrary isolation identified by the `Notification.Name` `"eventDidFinish"` with a `userInfo`
    /// dictionary containing the key `"duration"` as an `NSNumber`, an app could post and observe the notification with the following ``AsyncMessage``:
    ///
    /// ```swift
    /// struct EventDidFinish: NotificationCenter.Backport.AsyncMessage {
    ///     typealias Subject = Event
    ///     static var name: Notification.Name { Notification.Name("eventDidFinish") }
    ///
    ///     var duration: Int
    ///
    ///     static func makeNotification(_ message: Self) -> Notification {
    ///         return Notification(name: Self.name, userInfo: ["duration": NSNumber(message.duration)])
    ///     }
    ///
    ///     static func makeMessage(_ notification: Notification) -> Self? {
    ///         guard let userInfo = notification.userInfo,
    ///               let duration = userInfo["duration"] as? Int
    ///         else {
    ///             return nil
    ///         }
    ///
    ///         return Self(duration: duration)
    ///     }
    /// }
    /// ```
    ///
    /// With this definition, an observer for this `AsyncMessage` type receives information even if the poster used the `Notification` equivalent, and vice versa.
    public protocol AsyncMessage: Sendable {
        /// A type which you can optionally post and observe along with this `AsyncMessage`.
        associatedtype Subject

        /// A optional name corresponding to this type, used to interoperate with notification posters and observers.
        static var name: Notification.Name { get }

        /// Converts a posted notification into this asynchronous message type for any observers.
        ///
        /// To implement this method in your own `AsyncMessage` conformance, retrieve values from the `Notification`'s `userInfo` and set them as properties on the message.
        /// - Parameter notification: The posted `Notification`.
        /// - Returns: The converted `AsyncMessage`, or `nil` if conversion is not possible.
        static func makeMessage(_ notification: Notification) -> Self?

        /// Converts a posted asynchronous message into a notification for any observers.
        ///
        /// To implement this method in your own `AsyncMessage` conformance, use the properties defined by the message to populate the `Notification`'s `userInfo`.
        /// - Parameters:
        ///   - message: The posted `AsyncMessage`.
        /// - Returns: The converted `Notification`.
        static func makeNotification(_ message: Self) -> Notification
    }
}

extension NotificationCenter.Backport.AsyncMessage {
    public static func makeMessage(_ notification: Notification) -> Self? { return nil }
    public static func makeNotification(_ message: Self) -> Notification { return Notification(name: Self.name) }

    // Default Message name is the fully-qualified type name, suitable when Notification-compatibility isn't needed
    public static var name: Notification.Name {
        // Similar to String(describing:)
        return Notification.Name(rawValue: _typeName(Self.self))
    }
}

extension NotificationCenter {
    /// Adds an observer to a center for messages delivered asynchronously with a given subject and identifier.
    /// - Parameters:
    ///   - subject: The subject to observe. Specify a metatype to observe all values for a given type.
    ///   - identifier: An identifier representing a specific message type.
    ///   - observer: A closure to execute when receiving a message.
    /// - Returns: A token representing the observation registration with the given notification center. Retain this token for as long as you need to receive messages.
    public func addObserver<Identifier: Backport.MessageIdentifier, Message: Backport.AsyncMessage>(
        of subject: Message.Subject,
        for identifier: Identifier,
        using observer: @escaping @Sendable (Message) async -> Void)
    -> Backport.ObservationToken where Identifier.MessageType == Message,
                                       Message.Subject: AnyObject
    {
        _addAsyncObserver(Identifier.MessageType.self, subject: subject, observer: observer)
    }

    /// Adds an observer to a center for messages delivered asynchronously with a given subject and message type.
    /// - Parameters:
    ///   - subject: The metatype to observe all values for a given type.
    ///   - identifier: An identifier representing a specific message type.
    ///   - observer: A closure to execute when receiving a message.
    /// - Returns: A token representing the observation registration with the given notification center. Retain this token for as long as you need to receive messages.
    public func addObserver<Identifier: Backport.MessageIdentifier, Message: Backport.AsyncMessage>(
        of subject: Message.Subject.Type,
        for identifier: Identifier,
        using observer: @escaping @Sendable (Message) async -> Void)
    -> Backport.ObservationToken where Identifier.MessageType == Message {
        _addAsyncObserver(Identifier.MessageType.self, subject: nil, observer: observer)
    }

    /// Adds an observer to a center for messages delivered asynchronously with a given subject and message type.
    /// - Parameters:
    ///   - subject: The subject to observe. Specify a metatype to observe all values for a given type.
    ///   - messageType: The message type to be observed.
    ///   - observer: A closure to execute when receiving a message.
    /// - Returns: A token representing the observation registration with the given notification center.  Retain this token for as long as you need to receive messages.
    public func addObserver<Message: Backport.AsyncMessage>(
        of subject: Message.Subject? = nil,
        for messageType: Message.Type,
        using observer: @escaping @Sendable (Message) async -> Void)
    -> Backport.ObservationToken where Message.Subject: AnyObject {
        _addAsyncObserver(Message.self, subject: subject, observer: observer)
    }

    /// Posts a given asynchronous message to the notification center.
    /// - Parameters:
    ///   - message: The message to post.
    ///   - subject: The subject instance that corresponds to the message.
    public func post<Message: Backport.AsyncMessage>(_ message: Message, subject: Message.Subject) where Message.Subject: AnyObject {
        _post(message: message, subject: subject)
    }

    /// Posts a given asynchronous message to the notification center.
    /// - Parameters:
    ///   - message: The message to post.
    public func post<Message: Backport.AsyncMessage>(_ message: Message) {
        _post(message: message)
    }
}

extension NotificationCenter {
    fileprivate func _addAsyncObserver<Message: Backport.AsyncMessage>(
        _ messageType: Message.Type,
        subject: Message.Subject?,
        observer: @escaping @Sendable (Message) async -> Void
    ) -> Backport.ObservationToken {
        Backport.ObservationToken(center: self, token: _addObserver(Message.name, object: subject) { payload in
            guard
                let payload: Message = NotificationCenter._messageFromNotification(payload)
            else { return }
            self.asyncObserverQueue.enqueue {
                await observer(payload)
            }
        })
    }

    internal static func _messageFromNotification<Message: Backport.AsyncMessage>(_ notification: Notification) -> Message? {
        if let message = notification.userInfo?[Backport.NotificationMessageKey.key] as? Message {
            // Message posted, message observed
            return message
        } else if let message = Message.makeMessage(notification) {
            // Notification posted, message observed
            return message
        } else {
            // Notification posted, unable to make a message
            NotificationCenterBackportDiagnostics.reportUnconvertibleNotification(messageType: Message.self)
            return nil
        }
    }

    fileprivate func _post<Message: Backport.AsyncMessage>(message: Message, subject: Message.Subject? = nil) {
        var notification = Message.makeNotification(message)

        notification.name = Message.name
        notification.object = subject

        var userInfo = notification.userInfo.take() ?? [:]
        userInfo[Backport.NotificationMessageKey.key] = message
        notification.userInfo = userInfo

        post(notification)
    }
}
