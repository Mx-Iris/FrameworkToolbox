import MacroTesting
import Testing

@testable import OSToolboxMacros

// MARK: - @Signpostable

@Suite(.macros(["Signpostable": SignpostableMacro.self]))
struct SignpostableMacroTests {

    // MARK: Access levels

    @Test func defaultAccessLevel() {
        assertMacro {
            """
            @Signpostable
            struct SyncService { }
            """
        } expansion: {
            """
            struct SyncService { 

                private nonisolated static var signpostCategory: String {
                    "SyncService"
                }

                private nonisolated static var signpostSubsystem: String {
                    "SyncService"
                }

                private nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

                private nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                private nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                private nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                private nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    @Test func publicAccessLevel() {
        assertMacro {
            """
            @Signpostable(.public)
            struct SyncService { }
            """
        } expansion: {
            """
            struct SyncService { 

                public nonisolated static var signpostCategory: String {
                    "SyncService"
                }

                public nonisolated static var signpostSubsystem: String {
                    "SyncService"
                }

                public nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

                public nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                public nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                public nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                public nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                public nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                public nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                public nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                public nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    @Test func internalAccessLevelOmitsModifier() {
        assertMacro {
            """
            @Signpostable(.internal)
            struct SyncService { }
            """
        } expansion: {
            """
            struct SyncService { 

                nonisolated static var signpostCategory: String {
                    "SyncService"
                }

                nonisolated static var signpostSubsystem: String {
                    "SyncService"
                }

                nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

                nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    // MARK: Subsystem and category overrides

    @Test func customSubsystemAndCategory() {
        assertMacro {
            """
            @Signpostable(.internal, subsystem: "com.example.app", category: "Networking")
            final class NetworkService { }
            """
        } expansion: {
            """
            final class NetworkService { 

                nonisolated static var signpostCategory: String {
                    "Networking"
                }

                nonisolated static var signpostSubsystem: String {
                    "com.example.app"
                }

                nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

                nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    /// The system's points-of-interest category is what puts signposts on
    /// Instruments' default track, so pinning this spelling matters.
    @Test func pointsOfInterestCategory() {
        assertMacro {
            """
            @Signpostable(category: "PointsOfInterest")
            struct Launch { }
            """
        } expansion: {
            """
            struct Launch { 

                private nonisolated static var signpostCategory: String {
                    "PointsOfInterest"
                }

                private nonisolated static var signpostSubsystem: String {
                    "Launch"
                }

                private nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

                private nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                private nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                private nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                private nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    // MARK: Declaration kinds

    @Test func attachedToClass() {
        assertMacro {
            """
            @Signpostable
            final class SyncService { }
            """
        } expansion: {
            """
            final class SyncService { 

                private nonisolated static var signpostCategory: String {
                    "SyncService"
                }

                private nonisolated static var signpostSubsystem: String {
                    "SyncService"
                }

                private nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

                private nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                private nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                private nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                private nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    @Test func attachedToEnum() {
        assertMacro {
            """
            @Signpostable
            enum SyncService { }
            """
        } expansion: {
            """
            enum SyncService { 

                private nonisolated static var signpostCategory: String {
                    "SyncService"
                }

                private nonisolated static var signpostSubsystem: String {
                    "SyncService"
                }

                private nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

                private nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                private nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                private nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                private nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    @Test func attachedToActor() {
        assertMacro {
            """
            @Signpostable
            actor SyncService { }
            """
        } expansion: {
            """
            actor SyncService { 

                private nonisolated static var signpostCategory: String {
                    "SyncService"
                }

                private nonisolated static var signpostSubsystem: String {
                    "SyncService"
                }

                private nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

                private nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                private nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                private nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                private nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    // MARK: Protocols

    @Test func attachedToProtocol() {
        assertMacro {
            """
            @Signpostable
            protocol Networking { }
            """
        } expansion: {
            """
            protocol Networking { 

                static var signpostCategory: String {
                    get
                }

                static var signpostSubsystem: String {
                    get
                }

                static var _signpostLog: os.OSLog {
                    get
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                static var signposter: os.OSSignposter {
                    get
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                var signposter: os.OSSignposter {
                    get
                }
            }

            extension Networking {
                nonisolated static var signpostCategory: String {
                    String(describing: self)
                }

                nonisolated static var signpostSubsystem: String {
                    String(describing: self)
                }

                nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(for: self, subsystem: signpostSubsystem, category: signpostCategory)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(for: self, subsystem: signpostSubsystem, category: signpostCategory)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    @Test func attachedToPublicProtocol() {
        assertMacro {
            """
            @Signpostable(.public)
            public protocol Networking { }
            """
        } expansion: {
            """
            public protocol Networking { 

                static var signpostCategory: String {
                    get
                }

                static var signpostSubsystem: String {
                    get
                }

                static var _signpostLog: os.OSLog {
                    get
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                static var signposter: os.OSSignposter {
                    get
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                var signposter: os.OSSignposter {
                    get
                }
            }

            extension Networking {
                public nonisolated static var signpostCategory: String {
                    String(describing: self)
                }

                public nonisolated static var signpostSubsystem: String {
                    String(describing: self)
                }

                public nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(for: self, subsystem: signpostSubsystem, category: signpostCategory)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                public nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(for: self, subsystem: signpostSubsystem, category: signpostCategory)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                public nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                public nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                public nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                public nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                public nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }

    @Test func protocolWithoutRequirements() {
        assertMacro {
            """
            @Signpostable(asProtocolRequirement: false)
            protocol Networking { }
            """
        } expansion: {
            """
            protocol Networking { }

            extension Networking {
                nonisolated static var signpostCategory: String {
                    String(describing: self)
                }

                nonisolated static var signpostSubsystem: String {
                    String(describing: self)
                }

                nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(for: self, subsystem: signpostSubsystem, category: signpostCategory)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(for: self, subsystem: signpostSubsystem, category: signpostCategory)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
                }

                nonisolated static func makeSignpostID() -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog)
                }

                nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
                    os.OSSignpostID(log: _signpostLog, object: object)
                }
            }
            """
        }
    }
}

// MARK: - #signpost

@Suite(.macros(["signpost": SignpostMacro.self]))
struct SignpostMacroTests {

    // MARK: .event

    @Test func eventWithoutMessage() {
        assertMacro {
            """
            #signpost(.event, "tapped")
            """
        } expansion: {
            """
            {
                let signpostLog = Self._signpostLog
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    os.OSSignposter(logHandle: signpostLog).emitEvent("tapped", id: .exclusive)
                } else {
                    os_signpost(.event, log: signpostLog, name: "tapped", signpostID: .exclusive)
                }
            }()
            """
        }
    }

    @Test func eventWithMessage() {
        assertMacro {
            """
            #signpost(.event, "tapped", "index=\\(index, privacy: .public)")
            """
        } expansion: {
            #"""
            {
                let signpostLog = Self._signpostLog
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    os.OSSignposter(logHandle: signpostLog).emitEvent("tapped", id: .exclusive, "index=\(index, privacy: .public)")
                } else {
                    "\(index)".withCString { legacyArgument0 in
                        os_signpost(.event, log: signpostLog, name: "tapped", signpostID: .exclusive, "index=%{public}s", legacyArgument0)
                    }
                }
            }()
            """#
        }
    }

    @Test func eventUnderACategory() {
        assertMacro {
            """
            #signpost(.event, category: .pointsOfInterest, "tapped")
            """
        } expansion: {
            """
            {
                let signpostLog = Self._signpostLog(for: .pointsOfInterest)
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    os.OSSignposter(logHandle: signpostLog).emitEvent("tapped", id: .exclusive)
                } else {
                    os_signpost(.event, log: signpostLog, name: "tapped", signpostID: .exclusive)
                }
            }()
            """
        }
    }

    @Test func eventWithExplicitIdentifier() {
        assertMacro {
            """
            #signpost(.event, "tapped", id: Self.makeSignpostID())
            """
        } expansion: {
            """
            {
                let signpostLog = Self._signpostLog
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    os.OSSignposter(logHandle: signpostLog).emitEvent("tapped", id: Self.makeSignpostID())
                } else {
                    os_signpost(.event, log: signpostLog, name: "tapped", signpostID: Self.makeSignpostID())
                }
            }()
            """
        }
    }

    /// Several interpolated segments nest one `withCString` scope each, and keep
    /// their individual privacy levels while doing so.
    @Test func eventWithSeveralSegmentsAndMixedPrivacy() {
        assertMacro {
            """
            #signpost(.event, "tapped", "name=\\(name, privacy: .public) token=\\(token, privacy: .private)")
            """
        } expansion: {
            #"""
            {
                let signpostLog = Self._signpostLog
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    os.OSSignposter(logHandle: signpostLog).emitEvent("tapped", id: .exclusive, "name=\(name, privacy: .public) token=\(token, privacy: .private)")
                } else {
                    "\(name)".withCString { legacyArgument0 in
                        "\(token)".withCString { legacyArgument1 in
                            os_signpost(.event, log: signpostLog, name: "tapped", signpostID: .exclusive, "name=%{public}s token=%{private}s", legacyArgument0, legacyArgument1)
                        }
                    }
                }
            }()
            """#
        }
    }

    // MARK: .begin

    @Test func beginWithoutMessage() {
        assertMacro {
            """
            #signpost(.begin, "fetch")
            """
        } expansion: {
            """
            {
                let signpostLog = Self._signpostLog
                let signpostID = os.OSSignpostID(log: signpostLog)
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("fetch", id: signpostID)
                    return SignpostInterval(name: "fetch", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                } else {
                    os_signpost(.begin, log: signpostLog, name: "fetch", signpostID: signpostID)
                    return SignpostInterval(name: "fetch", signpostID: signpostID, log: signpostLog, intervalState: nil)
                }
            }()
            """
        }
    }

    @Test func beginWithMessage() {
        assertMacro {
            """
            #signpost(.begin, "fetch", "bytes=\\(byteCount)")
            """
        } expansion: {
            #"""
            {
                let signpostLog = Self._signpostLog
                let signpostID = os.OSSignpostID(log: signpostLog)
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("fetch", id: signpostID, "bytes=\(byteCount)")
                    return SignpostInterval(name: "fetch", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                } else {
                    "\(byteCount)".withCString { legacyArgument0 in
                        os_signpost(.begin, log: signpostLog, name: "fetch", signpostID: signpostID, "bytes=%{public}s", legacyArgument0)
                    }
                    return SignpostInterval(name: "fetch", signpostID: signpostID, log: signpostLog, intervalState: nil)
                }
            }()
            """#
        }
    }

    @Test func beginUnderACategoryWithExplicitIdentifier() {
        assertMacro {
            """
            #signpost(.begin, category: .pointsOfInterest, "fetch", id: Self.makeSignpostID(from: request))
            """
        } expansion: {
            """
            {
                let signpostLog = Self._signpostLog(for: .pointsOfInterest)
                let signpostID = Self.makeSignpostID(from: request)
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("fetch", id: signpostID)
                    return SignpostInterval(name: "fetch", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                } else {
                    os_signpost(.begin, log: signpostLog, name: "fetch", signpostID: signpostID)
                    return SignpostInterval(name: "fetch", signpostID: signpostID, log: signpostLog, intervalState: nil)
                }
            }()
            """
        }
    }

    // MARK: .end

    @Test func endWithoutMessage() {
        assertMacro {
            """
            #signpost(.end, uploadInterval)
            """
        } expansion: {
            """
            {
                let signpostLog = uploadInterval.log
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    os.OSSignposter(logHandle: signpostLog).endInterval(uploadInterval.name, uploadInterval.osSignpostIntervalState)
                } else {
                    os_signpost(.end, log: signpostLog, name: uploadInterval.name, signpostID: uploadInterval.signpostID)
                }
            }()
            """
        }
    }

    @Test func endWithMessage() {
        assertMacro {
            """
            #signpost(.end, uploadInterval, "ok=\\(true, privacy: .public)")
            """
        } expansion: {
            #"""
            {
                let signpostLog = uploadInterval.log
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    os.OSSignposter(logHandle: signpostLog).endInterval(uploadInterval.name, uploadInterval.osSignpostIntervalState, "ok=\(true, privacy: .public)")
                } else {
                    "\(true)".withCString { legacyArgument0 in
                        os_signpost(.end, log: signpostLog, name: uploadInterval.name, signpostID: uploadInterval.signpostID, "ok=%{public}s", legacyArgument0)
                    }
                }
            }()
            """#
        }
    }

    /// An interval reached through anything but a bare identifier is bound to a
    /// local first, so a call with side effects is not evaluated once per member
    /// access (name, identifier, log — three accesses).
    @Test func endWithANonTrivialIntervalExpression() {
        assertMacro {
            """
            #signpost(.end, intervals.removeLast())
            """
        } expansion: {
            """
            {
                let signpostInterval = intervals.removeLast()
                let signpostLog = signpostInterval.log
                if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                    os.OSSignposter(logHandle: signpostLog).endInterval(signpostInterval.name, signpostInterval.osSignpostIntervalState)
                } else {
                    os_signpost(.end, log: signpostLog, name: signpostInterval.name, signpostID: signpostInterval.signpostID)
                }
            }()
            """
        }
    }

    // MARK: Diagnostics

    @Test func unknownSignpostType() {
        assertMacro {
            """
            #signpost(.animationBegin, "fetch")
            """
        } diagnostics: {
            """
            #signpost(.animationBegin, "fetch")
            ┬──────────────────────────────────
            ╰─ 🛑 #signpost does not support '.animationBegin' — use .event, .begin, or .end
            """
        }
    }
}

// MARK: - #signpostInterval

@Suite(.macros(["signpostInterval": SignpostIntervalMacro.self]))
struct SignpostIntervalMacroTests {

    @Test func singleExpressionBodyGetsAnExplicitReturn() {
        assertMacro {
            """
            #signpostInterval("load") {
                readFromDisk()
            }
            """
        } expansion: {
            """
            {
                let signpostInterval = {
                    let signpostLog = Self._signpostLog
                    let signpostID = os.OSSignpostID(log: signpostLog)
                    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                        let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("load", id: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                    } else {
                        os_signpost(.begin, log: signpostLog, name: "load", signpostID: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: nil)
                    }
                }()
                defer {
                    {
                        let signpostLog = signpostInterval.log
                        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                            os.OSSignposter(logHandle: signpostLog).endInterval(signpostInterval.name, signpostInterval.osSignpostIntervalState)
                        } else {
                            os_signpost(.end, log: signpostLog, name: signpostInterval.name, signpostID: signpostInterval.signpostID)
                        }
                    }()
                }
                return readFromDisk()
            }()
            """
        }
    }

    @Test func multipleStatementBodyIsSplicedVerbatim() {
        assertMacro {
            """
            #signpostInterval("load") {
                let handle = openFile()
                defer { handle.close() }
                return handle.readAll()
            }
            """
        } expansion: {
            """
            {
                let signpostInterval = {
                    let signpostLog = Self._signpostLog
                    let signpostID = os.OSSignpostID(log: signpostLog)
                    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                        let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("load", id: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                    } else {
                        os_signpost(.begin, log: signpostLog, name: "load", signpostID: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: nil)
                    }
                }()
                defer {
                    {
                        let signpostLog = signpostInterval.log
                        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                            os.OSSignposter(logHandle: signpostLog).endInterval(signpostInterval.name, signpostInterval.osSignpostIntervalState)
                        } else {
                            os_signpost(.end, log: signpostLog, name: signpostInterval.name, signpostID: signpostInterval.signpostID)
                        }
                    }()
                }
                let handle = openFile()
                defer {
                    handle.close()
                }
                return handle.readAll()
            }()
            """
        }
    }

    /// The macro inserts no `try` of its own — the body's own effects are what
    /// the compiler infers the generated closure from.
    @Test func throwingBodyKeepsItsOwnTry() {
        assertMacro {
            """
            #signpostInterval("load") {
                try readFromDisk()
            }
            """
        } expansion: {
            """
            {
                let signpostInterval = {
                    let signpostLog = Self._signpostLog
                    let signpostID = os.OSSignpostID(log: signpostLog)
                    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                        let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("load", id: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                    } else {
                        os_signpost(.begin, log: signpostLog, name: "load", signpostID: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: nil)
                    }
                }()
                defer {
                    {
                        let signpostLog = signpostInterval.log
                        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                            os.OSSignposter(logHandle: signpostLog).endInterval(signpostInterval.name, signpostInterval.osSignpostIntervalState)
                        } else {
                            os_signpost(.end, log: signpostLog, name: signpostInterval.name, signpostID: signpostInterval.signpostID)
                        }
                    }()
                }
                return try readFromDisk()
            }()
            """
        }
    }

    @Test func asyncBodyKeepsItsOwnAwait() {
        assertMacro {
            """
            #signpostInterval("load") {
                await readFromDisk()
            }
            """
        } expansion: {
            """
            {
                let signpostInterval = {
                    let signpostLog = Self._signpostLog
                    let signpostID = os.OSSignpostID(log: signpostLog)
                    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                        let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("load", id: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                    } else {
                        os_signpost(.begin, log: signpostLog, name: "load", signpostID: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: nil)
                    }
                }()
                defer {
                    {
                        let signpostLog = signpostInterval.log
                        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                            os.OSSignposter(logHandle: signpostLog).endInterval(signpostInterval.name, signpostInterval.osSignpostIntervalState)
                        } else {
                            os_signpost(.end, log: signpostLog, name: signpostInterval.name, signpostID: signpostInterval.signpostID)
                        }
                    }()
                }
                return await readFromDisk()
            }()
            """
        }
    }

    @Test func voidBody() {
        assertMacro {
            """
            #signpostInterval("load") {
                recomputeLayout()
            }
            """
        } expansion: {
            """
            {
                let signpostInterval = {
                    let signpostLog = Self._signpostLog
                    let signpostID = os.OSSignpostID(log: signpostLog)
                    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                        let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("load", id: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                    } else {
                        os_signpost(.begin, log: signpostLog, name: "load", signpostID: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: nil)
                    }
                }()
                defer {
                    {
                        let signpostLog = signpostInterval.log
                        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                            os.OSSignposter(logHandle: signpostLog).endInterval(signpostInterval.name, signpostInterval.osSignpostIntervalState)
                        } else {
                            os_signpost(.end, log: signpostLog, name: signpostInterval.name, signpostID: signpostInterval.signpostID)
                        }
                    }()
                }
                return recomputeLayout()
            }()
            """
        }
    }

    @Test func underACategoryWithExplicitIdentifier() {
        assertMacro {
            """
            #signpostInterval("load", category: .pointsOfInterest, id: Self.makeSignpostID()) {
                readFromDisk()
            }
            """
        } expansion: {
            """
            {
                let signpostInterval = {
                    let signpostLog = Self._signpostLog(for: .pointsOfInterest)
                    let signpostID = Self.makeSignpostID()
                    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                        let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("load", id: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                    } else {
                        os_signpost(.begin, log: signpostLog, name: "load", signpostID: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: nil)
                    }
                }()
                defer {
                    {
                        let signpostLog = signpostInterval.log
                        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                            os.OSSignposter(logHandle: signpostLog).endInterval(signpostInterval.name, signpostInterval.osSignpostIntervalState)
                        } else {
                            os_signpost(.end, log: signpostLog, name: signpostInterval.name, signpostID: signpostInterval.signpostID)
                        }
                    }()
                }
                return readFromDisk()
            }()
            """
        }
    }

    @Test func bodyPassedAsAroundArgumentRatherThanTrailingClosure() {
        assertMacro {
            """
            #signpostInterval("load", around: { readFromDisk() })
            """
        } expansion: {
            """
            {
                let signpostInterval = {
                    let signpostLog = Self._signpostLog
                    let signpostID = os.OSSignpostID(log: signpostLog)
                    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                        let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval("load", id: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: intervalState)
                    } else {
                        os_signpost(.begin, log: signpostLog, name: "load", signpostID: signpostID)
                        return SignpostInterval(name: "load", signpostID: signpostID, log: signpostLog, intervalState: nil)
                    }
                }()
                defer {
                    {
                        let signpostLog = signpostInterval.log
                        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
                            os.OSSignposter(logHandle: signpostLog).endInterval(signpostInterval.name, signpostInterval.osSignpostIntervalState)
                        } else {
                            os_signpost(.end, log: signpostLog, name: signpostInterval.name, signpostID: signpostInterval.signpostID)
                        }
                    }()
                }
                return readFromDisk()
            }()
            """
        }
    }
}
