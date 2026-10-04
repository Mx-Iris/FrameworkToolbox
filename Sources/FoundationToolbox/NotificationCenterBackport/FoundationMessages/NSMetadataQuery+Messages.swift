import Foundation

// Foundation's predefined `NSMetadataQuery` messages. The conventions every
// file in `FoundationMessages/` follows are noted after
// `NotificationCenter.Backport` in `NotificationCenterBackport.swift`.

extension NSMetadataQuery {
    /// Backports of the messages Foundation declares on `NSMetadataQuery` from
    /// the 26 releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension NSMetadataQuery.Backport {
    /// A message a metadata query sends when it finishes the initial result-gathering phase of the query.
    public struct DidFinishGatheringMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = NSMetadataQuery

        public static var name: Notification.Name {
            .NSMetadataQueryDidFinishGathering
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message a metadata query sends when it starts the initial result-gathering phase of the query.
    public struct DidStartGatheringMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = NSMetadataQuery

        public static var name: Notification.Name {
            .NSMetadataQueryDidStartGathering
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<NSMetadataQuery.Backport.DidFinishGatheringMessage> {
    /// The identifier of `NSMetadataQuery.Backport.DidFinishGatheringMessage`.
    @_disfavoredOverload
    public static var didFinishGathering: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<NSMetadataQuery.Backport.DidStartGatheringMessage> {
    /// The identifier of `NSMetadataQuery.Backport.DidStartGatheringMessage`.
    @_disfavoredOverload
    public static var didStartGathering: Self { .init() }
}
