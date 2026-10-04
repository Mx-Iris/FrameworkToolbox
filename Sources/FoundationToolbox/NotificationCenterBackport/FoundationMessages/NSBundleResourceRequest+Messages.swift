import Foundation

// Foundation's predefined `NSBundleResourceRequest` message. The conventions
// every file in `FoundationMessages/` follows are noted after
// `NotificationCenter.Backport` in `NotificationCenterBackport.swift`.
//
// The availability below is Foundation's own for this message, less the 26
// gate: no macOS, and deprecated with on-demand resources from the 27 releases.

@available(macOS, unavailable)
@available(iOS, deprecated: 27, message: "Use Background Assets instead.")
@available(tvOS, deprecated: 27, message: "Use Background Assets instead.")
@available(watchOS, deprecated: 27, message: "Use Background Assets instead.")
@available(visionOS, deprecated: 27, message: "Use Background Assets instead.")
extension NSBundleResourceRequest {
    /// Backports of the messages Foundation declares on
    /// `NSBundleResourceRequest` from the 26 releases. See
    /// `NotificationCenter.Backport`.
    public enum Backport {}
}

@available(macOS, unavailable)
@available(iOS, deprecated: 27, message: "Use Background Assets instead.")
@available(tvOS, deprecated: 27, message: "Use Background Assets instead.")
@available(watchOS, deprecated: 27, message: "Use Background Assets instead.")
@available(visionOS, deprecated: 27, message: "Use Background Assets instead.")
extension NSBundleResourceRequest.Backport {
    /// A message the system sends when it detects the amount of available disk space getting low.
    public struct LowDiskSpaceMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = NSBundleResourceRequest

        public static var name: Notification.Name {
            .NSBundleResourceRequestLowDiskSpace
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

@available(macOS, unavailable)
@available(iOS, deprecated: 27, message: "Use Background Assets instead.")
@available(tvOS, deprecated: 27, message: "Use Background Assets instead.")
@available(watchOS, deprecated: 27, message: "Use Background Assets instead.")
@available(visionOS, deprecated: 27, message: "Use Background Assets instead.")
extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<NSBundleResourceRequest.Backport.LowDiskSpaceMessage> {
    /// The identifier of `NSBundleResourceRequest.Backport.LowDiskSpaceMessage`.
    @_disfavoredOverload
    public static var lowDiskSpace: Self { .init() }
}
