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
//  Sources/FoundationEssentials/NotificationCenter/MainActorMessage.swift at
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
    /// A protocol for creating types that you can post to a notification center and bind to the main actor.
    ///
    /// You post types conforming to `MainActorMessage` to a notification center using `post(_:subject:)` and observe them with `addObserver(of:for:using:)`. The notification center delivers `MainActorMessage` types synchronously when posted.
    ///
    /// For types that post on an arbitrary isolation, use ``AsyncMessage``.
    ///
    /// Each `MainActorMessage` is associated with a specific `Subject` type.
    ///
    /// For example, a `MainActorMessage` associated with the type `Event` could use the following declaration:
    ///
    /// ```swift
    /// struct EventDidStart: NotificationCenter.Backport.MainActorMessage {
    ///     typealias Subject = Event
    /// }
    /// ```
    ///
    /// `MainActorMessage` can use an optional ``MessageIdentifier`` type for context-aware observer registration:
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
    /// ### Notification Interoperability
    ///
    /// `MainActorMessage` includes optional interoperability with `Notification`, enabling posters and observers of both types
    /// to pass information.
    ///
    /// It does this by offering a ``makeMessage(_:)`` method that collects values from a `Notification`'s `userInfo` and populates properties on a new message.
    /// In the other direction, a ``makeNotification(_:)`` method collects the message's defined properties and loads them into a new notification's `userInfo` dictionary.
    ///
    /// For example, if there exists a `Notification` posted on `MainActor` identified by the `Notification.Name` `"eventDidFinish"` with a `userInfo`
    /// dictionary containing the key `"duration"` as an `NSNumber`, an app could post and observe the notification with the following `MainActorMessage`:
    ///
    /// ```swift
    /// struct EventDidFinish: NotificationCenter.Backport.MainActorMessage {
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
    /// With this definition, an observer for this `MainActorMessage` type receives information even if the poster used the `Notification` equivalent, and vice versa.
    public protocol MainActorMessage: SendableMetatype {
        /// A type which you can optionally post and observe along with this `MainActorMessage`.
        associatedtype Subject

        /// A optional name corresponding to this type, used to interoperate with notification posters and observers.
        static var name: Notification.Name { get }

        /// Converts a posted notification into this main actor message type for any observers.
        ///
        /// To implement this method in your own `MainActorMessage` conformance, retrieve values from the `Notification`'s `userInfo` and set them as properties on the message.
        /// - Parameter notification: The posted `Notification`.
        /// - Returns: The converted `MainActorMessage` or `nil` if conversion is not possible.
        @MainActor static func makeMessage(_ notification: Notification) -> Self?

        /// Converts a posted main actor message into a notification for any observers.
        ///
        /// To implement this method in your own `MainActorMessage` conformance, use the properties defined by the message to populate the `Notification`'s `userInfo`.
        /// - Parameters:
        ///   - message: The posted `MainActorMessage`.
        /// - Returns: The converted `Notification`.
        @MainActor static func makeNotification(_ message: Self) -> Notification
    }
}

extension NotificationCenter.Backport.MainActorMessage {
    @MainActor public static func makeMessage(_ notification: Notification) -> Self? { return nil }
    @MainActor public static func makeNotification(_ message: Self) -> Notification { return Notification(name: Self.name) }

    // Default Message name is the fully-qualified type name, suitable when Notification-compatibility isn't needed
    public static var name: Notification.Name {
        // Similar to String(describing:)
        return Notification.Name(rawValue: _typeName(Self.self))
    }
}

extension NotificationCenter {
    /// Adds an observer to a center for messages delivered on the main actor with a given subject and identifier.
    ///
    /// - Parameters:
    ///   - subject: The subject to observe. Specify a metatype to observe all values for a given type.
    ///   - identifier: An identifier representing a specific message type.
    ///   - observer: A closure to execute when receiving a message.
    /// - Returns: A token representing the observation registration with the given notification center.
    public func addObserver<Identifier: Backport.MessageIdentifier, Message: Backport.MainActorMessage>(
        of subject: Message.Subject,
        for identifier: Identifier,
        using observer: @escaping @MainActor (Message) -> Void)
    -> Backport.ObservationToken where Identifier.MessageType == Message,
                                       Message.Subject: AnyObject {
        _addMainActorObserver(subject: subject, observer: observer)
    }

    /// Adds an observer to a center for messages delivered on the main actor with a given subject and identifier.
    ///
    /// - Parameters:
    ///   - subject: The metatype to observe all values for a given type.
    ///   - identifier: An identifier representing a specific message type.
    ///   - observer: A closure to execute when receiving a message.
    /// - Returns: A token representing the observation registration with the given notification center.
    public func addObserver<Identifier: Backport.MessageIdentifier, Message: Backport.MainActorMessage>(
        of subject: Message.Subject.Type,
        for identifier: Identifier,
        using observer: @escaping @MainActor (Message) -> Void)
    -> Backport.ObservationToken where Identifier.MessageType == Message {
        _addMainActorObserver(subject: nil, observer: observer)
    }

    /// Adds an observer to a center for messages delivered on the main actor with a given subject and message type.
    /// - Parameters:
    ///   - subject: The subject to be observed. Specify a metatype to observe all values for a given type.
    ///   - messageType: The message type to be observed.
    ///   - observer: A closure to execute when receiving a message.
    /// - Returns: A token representing the observation registration with the given notification center.
    public func addObserver<Message: Backport.MainActorMessage>(
        of subject: Message.Subject? = nil,
        for messageType: Message.Type,
        using observer: @escaping @MainActor (Message) -> Void)
    -> Backport.ObservationToken where Message.Subject: AnyObject {
        _addMainActorObserver(subject: subject, observer: observer)
    }

    /// Posts a given main actor message to the notification center.
    /// - Parameters:
    ///   - message: The message to post.
    ///   - subject: The subject instance that corresponds to the message.
    @MainActor
    public func post<Message: Backport.MainActorMessage>(_ message: Message, subject: Message.Subject)
    where Message.Subject: AnyObject {
        MainActor.assertIsolated()
        _post(message: message, subject: subject)
    }

    /// Posts a given main actor message to the notification center.
    /// - Parameters:
    ///   - message: The message to post.
    @MainActor
    public func post<Message: Backport.MainActorMessage>(_ message: Message) {
        MainActor.assertIsolated()
        _post(message: message)
    }
}

extension NotificationCenter {
    fileprivate func _addMainActorObserver<Message: Backport.MainActorMessage>(
        subject: Message.Subject?,
        observer: @escaping @MainActor (Message) -> Void
    ) -> Backport.ObservationToken {
        nonisolated(unsafe) let observer = observer
        return Backport.ObservationToken(center: self, token: _addObserver(Message.name, object: subject) { notification in
            nonisolated(unsafe) let notification = notification
            MainActor.assumeIsolated {
                if let message: Message = NotificationCenter._messageFromNotification(notification) {
                    observer(message)
                }
            }
        })
    }

    @MainActor
    fileprivate static func _messageFromNotification<Message: Backport.MainActorMessage>(_ notification: Notification) -> Message? {
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

    @MainActor
    fileprivate func _post<Message: Backport.MainActorMessage>(message: Message, subject: Message.Subject? = nil) {
        var notification = Message.makeNotification(message)

        notification.name = Message.name
        notification.object = subject

        var userInfo = notification.userInfo.take() ?? [:]
        userInfo[Backport.NotificationMessageKey.key] = message
        notification.userInfo = userInfo

        post(notification)
    }
}
