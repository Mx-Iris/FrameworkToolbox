import Foundation

// Foundation's predefined `NSExtensionContext` messages. The conventions every
// file in `FoundationMessages/` follows are noted after
// `NotificationCenter.Backport` in `NotificationCenterBackport.swift`.
//
// The SDK keeps the four `NSExtensionHost…Notification` constants from macOS,
// but Foundation's messages exist there all the same, so on macOS each name is
// spelled as the string Foundation's getter returns.

extension NSExtensionContext {
    /// Backports of the messages Foundation declares on `NSExtensionContext`
    /// from the 26 releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension NSExtensionContext.Backport {
    /// A message the system sends when the extension’s host app moves from the inactive to the active state.
    public struct DidBecomeActiveMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = NSExtensionContext

        public static var name: Notification.Name {
            #if os(macOS)
            Notification.Name("NSExtensionHostDidBecomeActiveNotification")
            #else
            .NSExtensionHostDidBecomeActive
            #endif
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message the system sends when the extension’s host app begins running in the background.
    public struct DidEnterBackgroundMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = NSExtensionContext

        public static var name: Notification.Name {
            #if os(macOS)
            Notification.Name("NSExtensionHostDidEnterBackgroundNotification")
            #else
            .NSExtensionHostDidEnterBackground
            #endif
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message the system sends when the extension’s host app begins running in the foreground.
    public struct WillEnterForegroundMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = NSExtensionContext

        public static var name: Notification.Name {
            #if os(macOS)
            Notification.Name("NSExtensionHostWillEnterForegroundNotification")
            #else
            .NSExtensionHostWillEnterForeground
            #endif
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message the system sends when the extension’s host app moves from the active to the inactive state.
    public struct WillResignActiveMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = NSExtensionContext

        public static var name: Notification.Name {
            #if os(macOS)
            Notification.Name("NSExtensionHostWillResignActiveNotification")
            #else
            .NSExtensionHostWillResignActive
            #endif
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<NSExtensionContext.Backport.DidBecomeActiveMessage> {
    /// The identifier of `NSExtensionContext.Backport.DidBecomeActiveMessage`.
    @_disfavoredOverload
    public static var didBecomeActive: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<NSExtensionContext.Backport.DidEnterBackgroundMessage> {
    /// The identifier of `NSExtensionContext.Backport.DidEnterBackgroundMessage`.
    @_disfavoredOverload
    public static var didEnterBackground: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<NSExtensionContext.Backport.WillEnterForegroundMessage> {
    /// The identifier of `NSExtensionContext.Backport.WillEnterForegroundMessage`.
    @_disfavoredOverload
    public static var willEnterForeground: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<NSExtensionContext.Backport.WillResignActiveMessage> {
    /// The identifier of `NSExtensionContext.Backport.WillResignActiveMessage`.
    @_disfavoredOverload
    public static var willResignActive: Self { .init() }
}
