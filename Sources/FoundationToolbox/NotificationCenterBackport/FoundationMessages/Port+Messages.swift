import Foundation

// Foundation's predefined `Port` message. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension Port {
    /// Backports of the messages Foundation declares on `Port` from the 26
    /// releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension Port.Backport {
    /// A message the system sends when a port becomes invalid.
    public struct DidBecomeInvalidMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = Port

        public static var name: Notification.Name {
            Port.didBecomeInvalidNotification
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<Port.Backport.DidBecomeInvalidMessage> {
    /// The identifier of `Port.Backport.DidBecomeInvalidMessage`.
    @_disfavoredOverload
    public static var didBecomeInvalid: Self { .init() }
}
