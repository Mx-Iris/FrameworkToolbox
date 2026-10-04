import Foundation

// Foundation's predefined `Locale` message. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension Locale {
    /// Backports of the messages Foundation declares on `Locale` from the 26
    /// releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension Locale.Backport {
    /// A message the system sends when the current locale changes.
    public struct CurrentLocaleDidChangeMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = Locale

        public static var name: Notification.Name {
            NSLocale.currentLocaleDidChangeNotification
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<Locale.Backport.CurrentLocaleDidChangeMessage> {
    /// The identifier of `Locale.Backport.CurrentLocaleDidChangeMessage`.
    @_disfavoredOverload
    public static var currentLocaleDidChange: Self { .init() }
}
