import Foundation

// Foundation's predefined `FileManager` message. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension FileManager {
    /// Backports of the messages Foundation declares on `FileManager` from the
    /// 26 releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension FileManager.Backport {
    /// A message a file manager sends after the iCloud (“ubiquity”) identity changes.
    public struct UbiquityIdentityDidChangeMessage: NotificationCenter.Backport.MainActorMessage, Sendable {
        public typealias Subject = FileManager

        public static var name: Notification.Name {
            .NSUbiquityIdentityDidChange
        }

        public init() {}

        @MainActor
        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<FileManager.Backport.UbiquityIdentityDidChangeMessage> {
    /// The identifier of `FileManager.Backport.UbiquityIdentityDidChangeMessage`.
    @_disfavoredOverload
    public static var ubiquityIdentityDidChange: Self { .init() }
}
