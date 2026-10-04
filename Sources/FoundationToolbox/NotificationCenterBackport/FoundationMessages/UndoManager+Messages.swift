import Foundation

// Foundation's predefined `UndoManager` messages. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension UndoManager {
    /// Backports of the messages Foundation declares on `UndoManager` from the
    /// 26 releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension UndoManager.Backport {
    /// A message that an undo manager sends before undoing a change.
    public struct WillUndoChangeMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UndoManager

        public static var name: Notification.Name {
            .NSUndoManagerWillUndoChange
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message that an undo manager sends after undoing a change.
    public struct DidUndoChangeMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UndoManager

        public static var name: Notification.Name {
            .NSUndoManagerDidUndoChange
        }

        /// A Boolean value that indicates whether the undo group as a whole is discardable.
        public var groupIsDiscardable: Bool

        public init(groupIsDiscardable: Bool) {
            self.groupIsDiscardable = groupIsDiscardable
        }

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self(groupIsDiscardable: UndoManager.Backport.groupIsDiscardable(in: notification))
        }

        @MainActor
        public static func makeNotification(_ message: Self) -> Notification {
            UndoManager.Backport.notification(named: name, groupIsDiscardable: message.groupIsDiscardable)
        }
    }

    /// A message that an undo manager sends before redoing a change.
    public struct WillRedoChangeMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UndoManager

        public static var name: Notification.Name {
            .NSUndoManagerWillRedoChange
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message that an undo manager sends after redoing a change.
    public struct DidRedoChangeMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UndoManager

        public static var name: Notification.Name {
            .NSUndoManagerDidRedoChange
        }

        /// A Boolean value that indicates whether the undo group is discardable.
        public var groupIsDiscardable: Bool

        public init(groupIsDiscardable: Bool) {
            self.groupIsDiscardable = groupIsDiscardable
        }

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self(groupIsDiscardable: UndoManager.Backport.groupIsDiscardable(in: notification))
        }

        @MainActor
        public static func makeNotification(_ message: Self) -> Notification {
            UndoManager.Backport.notification(named: name, groupIsDiscardable: message.groupIsDiscardable)
        }
    }

    /// A message that an undo manager sends at certain checkpoints.
    public struct CheckpointMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UndoManager

        public static var name: Notification.Name {
            .NSUndoManagerCheckpoint
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message that an undo manager sends after opening an undo group.
    public struct DidOpenUndoGroupMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UndoManager

        public static var name: Notification.Name {
            .NSUndoManagerDidOpenUndoGroup
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message that an undo manager sends after closing an undo group.
    public struct DidCloseUndoGroupMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UndoManager

        public static var name: Notification.Name {
            .NSUndoManagerDidCloseUndoGroup
        }

        /// A Boolean value that indicates whether the undo group as a whole is discardable.
        public var groupIsDiscardable: Bool

        public init(groupIsDiscardable: Bool) {
            self.groupIsDiscardable = groupIsDiscardable
        }

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self(groupIsDiscardable: UndoManager.Backport.groupIsDiscardable(in: notification))
        }

        @MainActor
        public static func makeNotification(_ message: Self) -> Notification {
            UndoManager.Backport.notification(named: name, groupIsDiscardable: message.groupIsDiscardable)
        }
    }

    /// A message that an undo manager sends before closing an undo group.
    public struct WillCloseUndoGroupMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UndoManager

        public static var name: Notification.Name {
            .NSUndoManagerWillCloseUndoGroup
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension UndoManager.Backport {
    // Foundation shares one implementation between the three messages that
    // carry `groupIsDiscardable`. A missing or non-Boolean value reads as
    // `false` rather than failing the conversion, and the value is written back
    // as an `NSNumber` even when it is `false`.
    fileprivate static func groupIsDiscardable(in notification: Notification) -> Bool {
        notification.userInfo?[NSUndoManagerGroupIsDiscardableKey] as? Bool ?? false
    }

    fileprivate static func notification(named name: Notification.Name, groupIsDiscardable: Bool) -> Notification {
        Notification(
            name: name,
            object: nil,
            userInfo: [NSUndoManagerGroupIsDiscardableKey: NSNumber(value: groupIsDiscardable)]
        )
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UndoManager.Backport.WillUndoChangeMessage> {
    /// The identifier of `UndoManager.Backport.WillUndoChangeMessage`.
    @_disfavoredOverload
    public static var willUndoChange: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UndoManager.Backport.DidUndoChangeMessage> {
    /// The identifier of `UndoManager.Backport.DidUndoChangeMessage`.
    @_disfavoredOverload
    public static var didUndoChange: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UndoManager.Backport.WillRedoChangeMessage> {
    /// The identifier of `UndoManager.Backport.WillRedoChangeMessage`.
    @_disfavoredOverload
    public static var willRedoChange: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UndoManager.Backport.DidRedoChangeMessage> {
    /// The identifier of `UndoManager.Backport.DidRedoChangeMessage`.
    @_disfavoredOverload
    public static var didRedoChange: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UndoManager.Backport.CheckpointMessage> {
    /// The identifier of `UndoManager.Backport.CheckpointMessage`.
    @_disfavoredOverload
    public static var checkpoint: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UndoManager.Backport.DidOpenUndoGroupMessage> {
    /// The identifier of `UndoManager.Backport.DidOpenUndoGroupMessage`.
    @_disfavoredOverload
    public static var didOpenUndoGroup: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UndoManager.Backport.DidCloseUndoGroupMessage> {
    /// The identifier of `UndoManager.Backport.DidCloseUndoGroupMessage`.
    @_disfavoredOverload
    public static var didCloseUndoGroup: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UndoManager.Backport.WillCloseUndoGroupMessage> {
    /// The identifier of `UndoManager.Backport.WillCloseUndoGroupMessage`.
    @_disfavoredOverload
    public static var willCloseUndoGroup: Self { .init() }
}
