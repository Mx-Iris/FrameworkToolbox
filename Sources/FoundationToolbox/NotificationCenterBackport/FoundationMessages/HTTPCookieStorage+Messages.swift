import Foundation

// Foundation's predefined `HTTPCookieStorage` message. The conventions every
// file in `FoundationMessages/` follows are noted after
// `NotificationCenter.Backport` in `NotificationCenterBackport.swift`.

extension HTTPCookieStorage {
    /// Backports of the messages Foundation declares on `HTTPCookieStorage`
    /// from the 26 releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension HTTPCookieStorage.Backport {
    /// A message a cookie storage instance sends when its cookies change.
    public struct CookiesChangedMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = HTTPCookieStorage

        public static var name: Notification.Name {
            .NSHTTPCookieManagerCookiesChanged
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<HTTPCookieStorage.Backport.CookiesChangedMessage> {
    /// The identifier of `HTTPCookieStorage.Backport.CookiesChangedMessage`.
    @_disfavoredOverload
    public static var cookiesChanged: Self { .init() }
}
