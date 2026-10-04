import Foundation

// Foundation's predefined `TimeZone` message. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension TimeZone {
    /// Backports of the messages Foundation declares on `TimeZone` from the 26
    /// releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension TimeZone.Backport {
    /// A message the system sends when the system time zone changes.
    public struct SystemTimeZoneDidChangeMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = TimeZone

        public static var name: Notification.Name {
            .NSSystemTimeZoneDidChange
        }

        /// The previous system time zone, prior to the change.
        public var previousTimeZone: TimeZone?

        public init(previousTimeZone: TimeZone?) {
            self.previousTimeZone = previousTimeZone
        }

        // The system posts the previous time zone as the notification's object.
        // Anything else there reads as `nil` rather than failing the conversion.
        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self(previousTimeZone: notification.object as? TimeZone)
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<TimeZone.Backport.SystemTimeZoneDidChangeMessage> {
    /// The identifier of `TimeZone.Backport.SystemTimeZoneDidChangeMessage`.
    @_disfavoredOverload
    public static var systemTimeZoneDidChange: Self { .init() }
}
