import Foundation

// Foundation's predefined `Date` message. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension Date {
    /// Backports of the messages Foundation declares on `Date` from the 26
    /// releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension Date.Backport {
    /// A message the system sends when the system clock changes.
    public struct SystemClockDidChangeMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = Date

        public static var name: Notification.Name {
            .NSSystemClockDidChange
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<Date.Backport.SystemClockDidChangeMessage> {
    /// The identifier of `Date.Backport.SystemClockDidChangeMessage`.
    @_disfavoredOverload
    public static var systemClockDidChange: Self { .init() }
}
