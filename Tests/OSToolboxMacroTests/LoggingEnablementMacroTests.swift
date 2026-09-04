import MacroTesting
import Testing

@testable import OSToolboxMacros

// The `isEnabled:` switch and the generic-context branch, as they appear in the
// expansion. What they *do* at runtime is `LoggingControlTests`' job; that a
// generic type actually compiles with the macro on it is the job of
// `Sources/OSToolboxNoFoundationClient/GenericContexts.swift`, since no unit
// test can catch a compile error in a caller's file.

// MARK: - @Loggable(isEnabled:)

@Suite(.macros(["Loggable": LoggableMacro.self]))
struct LoggableEnablementTests {

    @Test func staticallyDisabledEmitsNoStorageAtAll() {
        assertMacro {
            """
            @Loggable(isEnabled: false)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                private nonisolated static var category: String {
                    "MyService"
                }

                private nonisolated static var subsystem: String {
                    "MyService"
                }

                private nonisolated static var _osLog: os.OSLog {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    .disabled
                }
            }
            """
        }
    }

    @Test func explicitlyEnabledMatchesOmittingTheArgument() {
        assertMacro {
            """
            @Loggable(isEnabled: true)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                private nonisolated static var category: String {
                    "MyService"
                }

                private nonisolated static var subsystem: String {
                    "MyService"
                }

                private nonisolated static let _enabledOSLog = os.OSLog(subsystem: subsystem, category: category)

                private nonisolated static var _osLog: os.OSLog {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return _enabledOSLog
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static let _enabledLogger = os.Logger(_enabledOSLog)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return _enabledLogger
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                }
            }
            """
        }
    }

    @Test func arbitraryExpressionIsCombinedWithTheRuntimeSwitches() {
        assertMacro {
            """
            @Loggable(isEnabled: DiagnosticFlags.verboseLogging)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                private nonisolated static var category: String {
                    "MyService"
                }

                private nonisolated static var subsystem: String {
                    "MyService"
                }

                private nonisolated static let _enabledOSLog = os.OSLog(subsystem: subsystem, category: category)

                private nonisolated static var _osLog: os.OSLog {
                    guard (DiagnosticFlags.verboseLogging) && LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return _enabledOSLog
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static let _enabledLogger = os.Logger(_enabledOSLog)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    guard (DiagnosticFlags.verboseLogging) && LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return _enabledLogger
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard (DiagnosticFlags.verboseLogging) && LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    guard (DiagnosticFlags.verboseLogging) && LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                }
            }
            """
        }
    }

    @Test func compoundExpressionIsTransplantedVerbatim() {
        assertMacro {
            """
            @Loggable(isEnabled: DiagnosticFlags.verbose || DiagnosticFlags.tracing)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                private nonisolated static var category: String {
                    "MyService"
                }

                private nonisolated static var subsystem: String {
                    "MyService"
                }

                private nonisolated static let _enabledOSLog = os.OSLog(subsystem: subsystem, category: category)

                private nonisolated static var _osLog: os.OSLog {
                    guard (DiagnosticFlags.verbose || DiagnosticFlags.tracing) && LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return _enabledOSLog
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static let _enabledLogger = os.Logger(_enabledOSLog)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    guard (DiagnosticFlags.verbose || DiagnosticFlags.tracing) && LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return _enabledLogger
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard (DiagnosticFlags.verbose || DiagnosticFlags.tracing) && LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    guard (DiagnosticFlags.verbose || DiagnosticFlags.tracing) && LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                }
            }
            """
        }
    }

    @Test func switchCombinesWithAccessLevelSubsystemAndCategory() {
        assertMacro {
            """
            @Loggable(.public, isEnabled: false, subsystem: "com.example.app", category: "Network")
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                public nonisolated static var category: String {
                    "Network"
                }

                public nonisolated static var subsystem: String {
                    "com.example.app"
                }

                public nonisolated static var _osLog: os.OSLog {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                public nonisolated static var logger: os.Logger {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                public nonisolated var logger: os.Logger {
                    Self.logger
                }

                public nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                public nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    .disabled
                }
            }
            """
        }
    }

    /// On a protocol the switch resolves inside the default implementations, so
    /// the requirements are unchanged and existing conformers keep compiling.
    @Test func protocolRequirementsAreUnchangedByTheSwitch() {
        assertMacro {
            """
            @Loggable(isEnabled: false)
            protocol Networking { }
            """
        } expansion: {
            """
            protocol Networking { 

                static var category: String {
                    get
                }

                static var subsystem: String {
                    get
                }

                static var _osLog: os.OSLog {
                    get
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                static var logger: os.Logger {
                    get
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                var logger: os.Logger {
                    get
                }
            }

            extension Networking {
                nonisolated static var category: String {
                    String(describing: self)
                }

                nonisolated static var subsystem: String {
                    String(describing: self)
                }

                nonisolated static var _osLog: os.OSLog {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                nonisolated static var logger: os.Logger {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                nonisolated var logger: os.Logger {
                    Self.logger
                }

                nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    .disabled
                }
            }
            """
        }
    }
}

// MARK: - @Loggable in a generic context

@Suite(.macros(["Loggable": LoggableMacro.self]))
struct LoggableGenericContextTests {

    /// Swift forbids static stored properties in a generic type, so the live
    /// handles come from the metatype-keyed runtime cache — the same one the
    /// protocol branch uses. Without this the macro simply could not be applied
    /// to a generic type, which is why it used to require declaring a protocol.
    @Test func genericStructResolvesHandlesThroughTheRuntimeCache() {
        assertMacro {
            """
            @Loggable
            struct GenericBox<Element> { }
            """
        } expansion: {
            """
            struct GenericBox<Element> { 

                private nonisolated static var category: String {
                    "GenericBox"
                }

                private nonisolated static var subsystem: String {
                    "GenericBox"
                }

                private nonisolated static var _osLog: os.OSLog {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                }
            }
            """
        }
    }

    @Test func genericClassResolvesHandlesThroughTheRuntimeCache() {
        assertMacro {
            """
            @Loggable
            final class GenericCache<Key, Value> { }
            """
        } expansion: {
            """
            final class GenericCache<Key, Value> { 

                private nonisolated static var category: String {
                    "GenericCache"
                }

                private nonisolated static var subsystem: String {
                    "GenericCache"
                }

                private nonisolated static var _osLog: os.OSLog {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                }
            }
            """
        }
    }

    @Test func constraintsAndWhereClausesDoNotChangeTheBranch() {
        assertMacro {
            """
            @Loggable
            struct ConstrainedStore<Element: Hashable, Metadata> where Metadata: Sendable { }
            """
        } expansion: {
            """
            struct ConstrainedStore<Element: Hashable, Metadata> where Metadata: Sendable { 

                private nonisolated static var category: String {
                    "ConstrainedStore"
                }

                private nonisolated static var subsystem: String {
                    "ConstrainedStore"
                }

                private nonisolated static var _osLog: os.OSLog {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                }
            }
            """
        }
    }

    @Test func genericEnumResolvesHandlesThroughTheRuntimeCache() {
        assertMacro {
            """
            @Loggable
            enum GenericOutcome<Success, Failure> { }
            """
        } expansion: {
            """
            enum GenericOutcome<Success, Failure> { 

                private nonisolated static var category: String {
                    "GenericOutcome"
                }

                private nonisolated static var subsystem: String {
                    "GenericOutcome"
                }

                private nonisolated static var _osLog: os.OSLog {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                }
            }
            """
        }
    }

    @Test func genericActorResolvesHandlesThroughTheRuntimeCache() {
        assertMacro {
            """
            @Loggable
            actor GenericCoordinator<Element> { }
            """
        } expansion: {
            """
            actor GenericCoordinator<Element> { 

                private nonisolated static var category: String {
                    "GenericCoordinator"
                }

                private nonisolated static var subsystem: String {
                    "GenericCoordinator"
                }

                private nonisolated static var _osLog: os.OSLog {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    guard LoggableMacro._isEnabled(category: category) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    guard LoggableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                }
            }
            """
        }
    }

    /// Statically off is the one case where both branches agree: no storage is
    /// emitted either way, so a generic type expands exactly like a plain one.
    @Test func staticallyDisabledGenericMatchesTheNonGenericExpansion() {
        assertMacro {
            """
            @Loggable(isEnabled: false)
            struct SilentGenericService<Element> { }
            """
        } expansion: {
            """
            struct SilentGenericService<Element> { 

                private nonisolated static var category: String {
                    "SilentGenericService"
                }

                private nonisolated static var subsystem: String {
                    "SilentGenericService"
                }

                private nonisolated static var _osLog: os.OSLog {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static var logger: os.Logger {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated var logger: os.Logger {
                    Self.logger
                }

                private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    .disabled
                }

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                    .disabled
                }
            }
            """
        }
    }

    /// A non-generic type nested inside a generic one is subject to the same
    /// restriction, and its own syntax tree cannot show that — the macro has to
    /// read `MacroExpansionContext.lexicalContext`.
    @Test func nonGenericNestedInsideGenericUsesTheRuntimeCache() {
        assertMacro {
            """
            struct OuterContainer<Element> {
                @Loggable
                struct NestedService { }
            }
            """
        } expansion: {
            """
            struct OuterContainer<Element> {
                struct NestedService { 

                    private nonisolated static var category: String {
                        "NestedService"
                    }

                    private nonisolated static var subsystem: String {
                        "NestedService"
                    }

                    private nonisolated static var _osLog: os.OSLog {
                        guard LoggableMacro._isEnabled(category: category) else {
                            return .disabled
                        }
                        return LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category)
                    }

                    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                    private nonisolated static var logger: os.Logger {
                        guard LoggableMacro._isEnabled(category: category) else {
                            return .disabled
                        }
                        return LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)
                    }

                    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                    private nonisolated var logger: os.Logger {
                        Self.logger
                    }

                    private nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                        guard LoggableMacro._isEnabled(category: category.name) else {
                            return .disabled
                        }
                        return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
                    }

                    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                    private nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                        guard LoggableMacro._isEnabled(category: category.name) else {
                            return .disabled
                        }
                        return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
                    }
            }
            }
            """
        }
    }
}

// MARK: - @Signpostable(isEnabled:)

@Suite(.macros(["Signpostable": SignpostableMacro.self]))
struct SignpostableEnablementTests {

    @Test func staticallyDisabledEmitsNoStorageAtAll() {
        assertMacro {
            """
            @Signpostable(isEnabled: false)
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

                private nonisolated static var _signpostLog: os.OSLog {
                    .disabled
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static var signposter: os.OSSignposter {
                    .disabled
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                private nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    .disabled
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    .disabled
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

    @Test func arbitraryExpressionIsCombinedWithTheRuntimeSwitches() {
        assertMacro {
            """
            @Signpostable(isEnabled: DiagnosticFlags.performanceTracing)
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
                    guard (DiagnosticFlags.performanceTracing) && SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignpostLog
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static var signposter: os.OSSignposter {
                    guard (DiagnosticFlags.performanceTracing) && SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return _enabledSignposter
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated var signposter: os.OSSignposter {
                    Self.signposter
                }

                private nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                    guard (DiagnosticFlags.performanceTracing) && SignpostableMacro._isEnabled(category: category.name) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                    guard (DiagnosticFlags.performanceTracing) && SignpostableMacro._isEnabled(category: category.name) else {
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

    @Test func genericTypeResolvesHandlesThroughTheRuntimeCache() {
        assertMacro {
            """
            @Signpostable
            struct GenericMeasured<Element> { }
            """
        } expansion: {
            """
            struct GenericMeasured<Element> { 

                private nonisolated static var signpostCategory: String {
                    "GenericMeasured"
                }

                private nonisolated static var signpostSubsystem: String {
                    "GenericMeasured"
                }

                private nonisolated static var _signpostLog: os.OSLog {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignpostLog(for: self, subsystem: signpostSubsystem, category: signpostCategory)
                }

                @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
                private nonisolated static var signposter: os.OSSignposter {
                    guard SignpostableMacro._isEnabled(category: signpostCategory) else {
                        return .disabled
                    }
                    return SignpostableMacro._sharedSignposter(for: self, subsystem: signpostSubsystem, category: signpostCategory)
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
}
