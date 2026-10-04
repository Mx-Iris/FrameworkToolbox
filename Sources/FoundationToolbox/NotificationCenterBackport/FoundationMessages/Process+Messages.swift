import Foundation

// Foundation's predefined `Process` message. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

// `Process` exists only on macOS — not under Mac Catalyst, where Foundation
// leaves this message out as well.
#if os(macOS)

extension Process {
    /// Backports of the messages Foundation declares on `Process` from macOS
    /// 26. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension Process.Backport {
    /// A message the system sends when a task stops operation.
    public struct DidTerminateMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = Process

        public static var name: Notification.Name {
            Process.didTerminateNotification
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<Process.Backport.DidTerminateMessage> {
    /// The identifier of `Process.Backport.DidTerminateMessage`.
    @_disfavoredOverload
    public static var didTerminate: Self { .init() }
}

#endif
