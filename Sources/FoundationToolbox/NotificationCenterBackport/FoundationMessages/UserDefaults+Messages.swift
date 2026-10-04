import Foundation

// Foundation's predefined `UserDefaults` messages. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension UserDefaults {
    /// Backports of the messages Foundation declares on `UserDefaults` from the
    /// 26 releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension UserDefaults.Backport {
    /// A message the system sends when a user-defaults setting changes.
    public struct DidChangeMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = UserDefaults

        public static var name: Notification.Name {
            UserDefaults.didChangeNotification
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message the system sends when the size of the data in the defaults database exceeds the maximum.
    public struct SizeLimitExceededMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = UserDefaults

        public static var name: Notification.Name {
            #if os(macOS)
            // The SDK keeps `sizeLimitExceededNotification` from macOS, but
            // Foundation's message exists there all the same and returns this.
            Notification.Name("com.apple.CFPreferences.byteCountLimitReached")
            #else
            UserDefaults.sizeLimitExceededNotification
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
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UserDefaults.Backport.DidChangeMessage> {
    /// The identifier of `UserDefaults.Backport.DidChangeMessage`.
    @_disfavoredOverload
    public static var didChange: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<UserDefaults.Backport.SizeLimitExceededMessage> {
    /// The identifier of `UserDefaults.Backport.SizeLimitExceededMessage`.
    @_disfavoredOverload
    public static var sizeLimitExceeded: Self { .init() }
}
