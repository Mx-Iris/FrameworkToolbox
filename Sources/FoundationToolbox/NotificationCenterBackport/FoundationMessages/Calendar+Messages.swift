import Foundation

// Foundation's predefined `Calendar` message. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension Calendar {
    /// Backports of the messages Foundation declares on `Calendar` from the 26
    /// releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension Calendar.Backport {
    /// A message sent by a calendar when the system’s calendar day changes, as determined by the system calendar, locale, and time zone.
    public struct CalendarDayChangedMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = Calendar

        public static var name: Notification.Name {
            .NSCalendarDayChanged
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<Calendar.Backport.CalendarDayChangedMessage> {
    /// The identifier of `Calendar.Backport.CalendarDayChangedMessage`.
    @_disfavoredOverload
    public static var calendarDayChanged: Self { .init() }
}
