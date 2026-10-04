//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
//  Adapted from swift-foundation (https://github.com/swiftlang/swift-foundation),
//  Sources/FoundationEssentials/NotificationCenter/NotificationCenter.swift at
//  3b9d8f4, distributed under the Apache License 2.0 with Runtime Library
//  Exception. See LICENSES/swift-foundation-LICENSE.
//
//  Modified for FrameworkToolbox: the namespace is new, the logger became
//  `@Loggable` + `#log`, and Foundation's private observer registration
//  (`-_addObserver:object:usingBlock:` / `-_removeObserver:`) is rebuilt on
//  the public selector-based API.
//

import Foundation
import SwiftStdlibToolbox

extension NotificationCenter {
    /// The typed message API that Foundation added to `NotificationCenter` in
    /// macOS 26, iOS 26, tvOS 26, watchOS 26 and visionOS 26, usable on every
    /// platform this package supports.
    ///
    /// Everything mirrors the Foundation API of the same name: the
    /// ``MainActorMessage`` and ``AsyncMessage`` protocols, the
    /// ``MessageIdentifier`` pattern, ``ObservationToken``, and the
    /// `addObserver(of:for:using:)`, `post(_:subject:)`,
    /// `messages(of:for:bufferSize:)` and `removeObserver(_:)` methods on
    /// `NotificationCenter` itself. Only the types moved — from
    /// `NotificationCenter` into this namespace — so adopting the pattern now
    /// and switching to Foundation's once the deployment target allows it is a
    /// matter of deleting `Backport.`.
    ///
    /// ```swift
    /// struct EventDidStart: NotificationCenter.Backport.MainActorMessage {
    ///     typealias Subject = Event
    /// }
    ///
    /// extension NotificationCenter.Backport.MessageIdentifier
    /// where Self == NotificationCenter.Backport.BaseMessageIdentifier<EventDidStart> {
    ///     static var didStart: Self { .init() }
    /// }
    ///
    /// let token = NotificationCenter.default.addObserver(of: event, for: .didStart) { message in
    ///     // Runs on the main actor.
    /// }
    /// NotificationCenter.default.post(EventDidStart(), subject: event)
    /// ```
    ///
    /// The two APIs share no message types. They meet only through
    /// `Notification`, exactly as either of them meets
    /// `post(name:object:userInfo:)`.
    ///
    /// ### Foundation's predefined messages
    ///
    /// The messages Foundation predefines for its own notifications are here
    /// as well, each in a `Backport` namespace on its subject type:
    /// `UndoManager.Backport.DidUndoChangeMessage` stands in for Foundation's
    /// `UndoManager.DidUndoChangeMessage`, and its identifier has Foundation's
    /// name, `.didUndoChange`. Wherever Foundation's own message is available
    /// — a deployment target of 26, or inside `if #available(macOS 26, *)` —
    /// that shorthand picks Foundation's message, not this one; name the type
    /// (`for: UndoManager.Backport.DidUndoChangeMessage.self`) to pick the
    /// backport there.
    public enum Backport {}
}

// Conventions for the predefined messages in `FoundationMessages/`, one file per
// subject type. Each reproduces Foundation's own implementation, read from
// Foundation 5027.0.69 on macOS 27.0; the
// `notification-center-backport-foundation-messages` proposal has the details.
//
// - Every identifier is `@_disfavoredOverload`. Without it the shorthand is
//   ambiguous wherever Foundation's identifier of the same name is available
//   too, so merely importing this module would break Foundation's own call
//   sites. With it, the solver still picks the backport where Foundation's is
//   unavailable, because an unavailable declaration scores worse than a
//   disfavored one (`SK_Unavailable` ranks above `SK_DisfavoredOverload` in
//   the compiler's `include/swift/Sema/Score.h`). `FoundationToolboxClient`
//   fails to compile if one goes missing — for every identifier that exists on
//   macOS, which leaves `.lowDiskSpace` unguarded.
// - A message without properties implements `makeMessage(_:)` as `Self()`,
//   whatever the notification's name, object or user info, as Foundation's
//   does. The protocol's default returns `nil`, which would silently drop
//   every notification the system posts, so the explicit ones must stay.
// - `name` is the SDK's constant for the notification. Where the SDK keeps that
//   constant from a platform on which Foundation offers the message anyway, it
//   is spelled as the string Foundation's getter returns.
// - Availability follows the notification's constant, not the 26 gate on
//   Foundation's types: only what the constant itself requires is declared.

/// The faults this API reports.
///
/// Foundation's copy reports a token removed from the wrong center through a
/// `Logger`, and a notification its `makeMessage(_:)` cannot convert through
/// `_NSRuntimeIssuesLog()` — `os_log_create("com.apple.runtime-issues",
/// "Foundation")`, written with Foundation's own Mach-O header as the sender,
/// which is what makes Xcode show it as a runtime issue. A library can only
/// get that treatment by passing a system image's header as its own, so here
/// all three are ordinary faults.
@Loggable(.internal, subsystem: "FoundationToolbox", category: "NotificationCenterBackport")
enum NotificationCenterBackportDiagnostics {
    static func reportTokenFromAnotherCenter(tokenCenter: NotificationCenter, receivingCenter: NotificationCenter) {
        #log(.fault, "Unable to remove observer. The provided token does not belong to this notification center. Expected: \(describe(tokenCenter), privacy: .public), got \(describe(receivingCenter), privacy: .public).")
    }

    static func reportUnconvertibleNotification(messageType: Any.Type) {
        #log(.fault, "Unable to deliver Notification to Message observer because \(String(describing: messageType), privacy: .public).makeMessage() returned nil. If this is unexpected, check or provide an implementation of makeMessage() which returns a non-nil value for this notification's payload.")
    }

    static func reportDroppedMessage(messageType: Any.Type) {
        #log(.fault, "Notification center message dropped due to buffer limit. Check sequence iterator frequently or increase buffer size. Message: \(String(describing: messageType), privacy: .public)")
    }

    private static func describe(_ center: NotificationCenter) -> String {
        "<\(_typeName(type(of: center))) 0x\(String(UInt(bitPattern: ObjectIdentifier(center)), radix: 16))>"
    }
}

extension NotificationCenter.Backport {
    /// The observer object a registration is made with — the public-API stand-in
    /// for the integer token Foundation's private
    /// `-_addObserver:object:usingBlock:` returns. Removing it from the center
    /// ends the registration.
    ///
    /// Registration goes through the selector-based
    /// `addObserver(_:selector:name:object:)` rather than the block-based
    /// `addObserver(forName:object:queue:using:)` because of what each keeps
    /// alive. The block-based call creates an observer object that Foundation
    /// itself retains until the registration is removed, and that object
    /// retains the center — so a center made with `NotificationCenter()` could
    /// not deallocate while any token was live. Foundation's private call
    /// retains neither, and neither does the selector-based one: the center
    /// references its observers weakly, and nothing references the center.
    /// Delivery is the same for all three: synchronous on the posting thread,
    /// names matched by value and objects by identity.
    final class NotificationObserverToken: NSObject, Sendable {
        private let block: @Sendable (Notification) -> Void

        init(block: @escaping @Sendable (Notification) -> Void) {
            self.block = block
        }

        @objc func deliver(_ notification: Notification) {
            block(notification)
        }
    }
}

extension NotificationCenter {
    // Stands in for Foundation's private `-_addObserver:object:usingBlock:`,
    // under the same name so that the call sites read as they do upstream.
    internal func _addObserver(_ name: Notification.Name, object: Any?, using block: @escaping @Sendable (Notification) -> Void) -> Backport.NotificationObserverToken {
        let token = Backport.NotificationObserverToken(block: block)
        addObserver(token, selector: #selector(Backport.NotificationObserverToken.deliver(_:)), name: name, object: object)
        return token
    }

    // Stands in for Foundation's private `-_removeObserver:`. Going through
    // `removeObserver(_:)` lets a subclass that overrides it see the removal,
    // which Foundation's version also arranges for subclasses.
    internal func _removeObserver(_ token: Backport.NotificationObserverToken) {
        removeObserver(token)
    }
}
