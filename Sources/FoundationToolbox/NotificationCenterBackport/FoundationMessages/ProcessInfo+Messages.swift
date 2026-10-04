import Foundation

// Foundation's predefined `ProcessInfo` messages. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension ProcessInfo {
    /// Backports of the messages Foundation declares on `ProcessInfo` from the
    /// 26 releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension ProcessInfo.Backport {
    /// A message the system sends when the device’s power state changes.
    @available(macOS 12, *)
    public struct PowerStateDidChangeMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = ProcessInfo

        public static var name: Notification.Name {
            .NSProcessInfoPowerStateDidChange
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message the system sends when the device’s thermal state changes.
    public struct ThermalStateDidChangeMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = ProcessInfo

        public static var name: Notification.Name {
            ProcessInfo.thermalStateDidChangeNotification
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }
}

@available(macOS 12, *)
extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<ProcessInfo.Backport.PowerStateDidChangeMessage> {
    /// The identifier of `ProcessInfo.Backport.PowerStateDidChangeMessage`.
    @_disfavoredOverload
    public static var powerStateDidChange: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<ProcessInfo.Backport.ThermalStateDidChangeMessage> {
    /// The identifier of `ProcessInfo.Backport.ThermalStateDidChangeMessage`.
    @_disfavoredOverload
    public static var thermalStateDidChange: Self { .init() }
}
