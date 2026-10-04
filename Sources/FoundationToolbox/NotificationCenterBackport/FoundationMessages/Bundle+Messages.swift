import Foundation

// Foundation's predefined `Bundle` message. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension Bundle {
    /// Backports of the messages Foundation declares on `Bundle` from the 26
    /// releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension Bundle.Backport {
    /// A message a bundle sends when it dynamically loads a class.
    public struct DidLoadMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = Bundle

        public static var name: Notification.Name {
            Bundle.didLoadNotification
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<Bundle.Backport.DidLoadMessage> {
    /// The identifier of `Bundle.Backport.DidLoadMessage`.
    @_disfavoredOverload
    public static var didLoad: Self { .init() }
}
