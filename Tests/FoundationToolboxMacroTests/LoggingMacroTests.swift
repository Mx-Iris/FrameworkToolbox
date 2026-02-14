import MacroTesting
import Testing

@testable import FoundationToolboxMacros

// MARK: - @Loggable

@Suite(.macros(["Loggable": LoggableMacro.self]))
struct LoggableMacroTests {

    // MARK: Access levels

    @Test func defaultAccessLevel() {
        assertMacro {
            """
            @Loggable
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                static var category: String {
                    "MyService"
                }

                static var subsystem: String {
                    Bundle.main.bundleIdentifier ?? "MyService"
                }

                static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }

    @Test func privateAccessLevel() {
        assertMacro {
            """
            @Loggable(.private)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                private static var category: String {
                    "MyService"
                }

                private static var subsystem: String {
                    Bundle.main.bundleIdentifier ?? "MyService"
                }

                private static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }

    @Test func publicAccessLevel() {
        assertMacro {
            """
            @Loggable(.public)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                public static var category: String {
                    "MyService"
                }

                public static var subsystem: String {
                    Bundle.main.bundleIdentifier ?? "MyService"
                }

                public static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                public static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                public var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }

    @Test func internalAccessLevel() {
        assertMacro {
            """
            @Loggable(.internal)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                static var category: String {
                    "MyService"
                }

                static var subsystem: String {
                    Bundle.main.bundleIdentifier ?? "MyService"
                }

                static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }

    // MARK: Type variants

    @Test func classUseBundleForSelf() {
        assertMacro {
            """
            @Loggable(.private)
            class MyService { }
            """
        } expansion: {
            """
            class MyService { 

                private static var category: String {
                    "MyService"
                }

                private static var subsystem: String {
                    Bundle(for: self).bundleIdentifier ?? "MyService"
                }

                private static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                private var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }

    @Test func enumType() {
        assertMacro {
            """
            @Loggable
            enum MyEvent { }
            """
        } expansion: {
            """
            enum MyEvent { 

                static var category: String {
                    "MyEvent"
                }

                static var subsystem: String {
                    Bundle.main.bundleIdentifier ?? "MyEvent"
                }

                static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }

    @Test func actorType() {
        assertMacro {
            """
            @Loggable
            actor MyActor { }
            """
        } expansion: {
            """
            actor MyActor {\u{0020}

                static var category: String {
                    "MyActor"
                }

                static var subsystem: String {
                    Bundle.main.bundleIdentifier ?? "MyActor"
                }

                static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }

    @Test func fileprivateAccessLevel() {
        assertMacro {
            """
            @Loggable(.fileprivate)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                fileprivate static var category: String {
                    "MyService"
                }

                fileprivate static var subsystem: String {
                    Bundle.main.bundleIdentifier ?? "MyService"
                }

                fileprivate static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                fileprivate static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                fileprivate var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }

    @Test func packageAccessLevel() {
        assertMacro {
            """
            @Loggable(.package)
            struct MyService { }
            """
        } expansion: {
            """
            struct MyService { 

                package static var category: String {
                    "MyService"
                }

                package static var subsystem: String {
                    Bundle.main.bundleIdentifier ?? "MyService"
                }

                package static let _osLog = OSLog(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                package static let logger = os.Logger(subsystem: subsystem, category: category)

                @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
                package var logger: os.Logger {
                    Self.logger
                }
            }
            """
        }
    }
}

// MARK: - #log

@Suite(.macros(["log": LogMacro.self]))
struct LogMacroTests {

    // MARK: Log levels

    @Test func debugLevel() {
        assertMacro {
            """
            #log(.debug, "Hello")
            """
        } expansion: {
            """
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("Hello")
                } else {
                    os_log(.debug, log: Self._osLog, "Hello")
                }
            }()
            """
        }
    }

    @Test func infoLevel() {
        assertMacro {
            """
            #log(.info, "Hello")
            """
        } expansion: {
            """
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.info("Hello")
                } else {
                    os_log(.info, log: Self._osLog, "Hello")
                }
            }()
            """
        }
    }

    @Test func defaultLevel() {
        assertMacro {
            """
            #log(.default, "Hello")
            """
        } expansion: {
            """
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.notice("Hello")
                } else {
                    os_log(.default, log: Self._osLog, "Hello")
                }
            }()
            """
        }
    }

    @Test func errorLevel() {
        assertMacro {
            """
            #log(.error, "Hello")
            """
        } expansion: {
            """
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.error("Hello")
                } else {
                    os_log(.error, log: Self._osLog, "Hello")
                }
            }()
            """
        }
    }

    @Test func faultLevel() {
        assertMacro {
            """
            #log(.fault, "Hello")
            """
        } expansion: {
            """
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.critical("Hello")
                } else {
                    os_log(.fault, log: Self._osLog, "Hello")
                }
            }()
            """
        }
    }

    // MARK: Privacy

    @Test func publicPrivacy() {
        assertMacro {
            """
            #log(.debug, "Value: \\(x, privacy: .public)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("Value: \(x, privacy: .public)")
                } else {
                    os_log(.debug, log: Self._osLog, "Value: %{public}@", "\(x)")
                }
            }()
            """#
        }
    }

    @Test func privatePrivacy() {
        assertMacro {
            """
            #log(.debug, "Value: \\(x, privacy: .private)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("Value: \(x, privacy: .private)")
                } else {
                    os_log(.debug, log: Self._osLog, "Value: %{private}@", "\(x)")
                }
            }()
            """#
        }
    }

    @Test func sensitiveMapToPrivate() {
        assertMacro {
            """
            #log(.debug, "Value: \\(x, privacy: .sensitive)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("Value: \(x, privacy: .sensitive)")
                } else {
                    os_log(.debug, log: Self._osLog, "Value: %{private}@", "\(x)")
                }
            }()
            """#
        }
    }

    @Test func autoDefaultToPublic() {
        assertMacro {
            """
            #log(.debug, "Value: \\(x, privacy: .auto)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("Value: \(x, privacy: .auto)")
                } else {
                    os_log(.debug, log: Self._osLog, "Value: %{public}@", "\(x)")
                }
            }()
            """#
        }
    }

    @Test func noPrivacyDefaultToPublic() {
        assertMacro {
            """
            #log(.debug, "Value: \\(x)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("Value: \(x)")
                } else {
                    os_log(.debug, log: Self._osLog, "Value: %{public}@", "\(x)")
                }
            }()
            """#
        }
    }

    @Test func privateWithMask() {
        assertMacro {
            """
            #log(.debug, "Value: \\(x, privacy: .private(mask: .hash))")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("Value: \(x, privacy: .private(mask: .hash))")
                } else {
                    os_log(.debug, log: Self._osLog, "Value: %{private}@", "\(x)")
                }
            }()
            """#
        }
    }

    // MARK: Multiple interpolations

    @Test func mixedPrivacy() {
        assertMacro {
            """
            #log(.error, "\\(a, privacy: .public) and \\(b, privacy: .private)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.error("\(a, privacy: .public) and \(b, privacy: .private)")
                } else {
                    os_log(.error, log: Self._osLog, "%{public}@ and %{private}@", "\(a)", "\(b)")
                }
            }()
            """#
        }
    }

    @Test func multipleInterpolationsWithSensitive() {
        assertMacro {
            """
            #log(.info, "user: \\(name, privacy: .public) secret: \\(token, privacy: .sensitive) id: \\(id)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.info("user: \(name, privacy: .public) secret: \(token, privacy: .sensitive) id: \(id)")
                } else {
                    os_log(.info, log: Self._osLog, "user: %{public}@ secret: %{private}@ id: %{public}@", "\(name)", "\(token)", "\(id)")
                }
            }()
            """#
        }
    }

    // MARK: Plain string

    @Test func plainString() {
        assertMacro {
            """
            #log(.info, "Hello world")
            """
        } expansion: {
            """
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.info("Hello world")
                } else {
                    os_log(.info, log: Self._osLog, "Hello world")
                }
            }()
            """
        }
    }

    // MARK: Format parameter passthrough

    @Test func formatParameterStrippedInLegacy() {
        assertMacro {
            """
            #log(.debug, "hex: \\(x, format: .hex, privacy: .public)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("hex: \(x, format: .hex, privacy: .public)")
                } else {
                    os_log(.debug, log: Self._osLog, "hex: %{public}@", "\(x)")
                }
            }()
            """#
        }
    }

    @Test func alignParameterStrippedInLegacy() {
        assertMacro {
            """
            #log(.info, "name: \\(s, align: .left(columns: 20), privacy: .public)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.info("name: \(s, align: .left(columns: 20), privacy: .public)")
                } else {
                    os_log(.info, log: Self._osLog, "name: %{public}@", "\(s)")
                }
            }()
            """#
        }
    }

    @Test func formatAndAlignAndPrivacyCombined() {
        assertMacro {
            """
            #log(.debug, "val: \\(n, format: .decimal(minDigits: 4), align: .right(columns: 10), privacy: .private)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("val: \(n, format: .decimal(minDigits: 4), align: .right(columns: 10), privacy: .private)")
                } else {
                    os_log(.debug, log: Self._osLog, "val: %{private}@", "\(n)")
                }
            }()
            """#
        }
    }

    @Test func formatOnlyNoPrivacy() {
        assertMacro {
            """
            #log(.info, "pi: \\(pi, format: .fixed(precision: 2))")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.info("pi: \(pi, format: .fixed(precision: 2))")
                } else {
                    os_log(.info, log: Self._osLog, "pi: %{public}@", "\(pi)")
                }
            }()
            """#
        }
    }

    // MARK: Percent literal escaping

    @Test func percentLiteralEscapedInLegacy() {
        assertMacro {
            """
            #log(.info, "100% done: \\(x)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.info("100% done: \(x)")
                } else {
                    os_log(.info, log: Self._osLog, "100%% done: %{public}@", "\(x)")
                }
            }()
            """#
        }
    }

    // MARK: Mask variants

    @Test func sensitiveWithMask() {
        assertMacro {
            """
            #log(.error, "token: \\(t, privacy: .sensitive(mask: .hash))")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.error("token: \(t, privacy: .sensitive(mask: .hash))")
                } else {
                    os_log(.error, log: Self._osLog, "token: %{private}@", "\(t)")
                }
            }()
            """#
        }
    }

    @Test func autoWithMask() {
        assertMacro {
            """
            #log(.debug, "val: \\(v, privacy: .auto(mask: .hash))")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("val: \(v, privacy: .auto(mask: .hash))")
                } else {
                    os_log(.debug, log: Self._osLog, "val: %{public}@", "\(v)")
                }
            }()
            """#
        }
    }

    // MARK: Interpolation only (no surrounding literal)

    @Test func interpolationOnly() {
        assertMacro {
            """
            #log(.debug, "\\(value)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.debug("\(value)")
                } else {
                    os_log(.debug, log: Self._osLog, "%{public}@", "\(value)")
                }
            }()
            """#
        }
    }

    // MARK: Complex expressions

    @Test func complexExpression() {
        assertMacro {
            """
            #log(.info, "count: \\(items.count, privacy: .public)")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.info("count: \(items.count, privacy: .public)")
                } else {
                    os_log(.info, log: Self._osLog, "count: %{public}@", "\(items.count)")
                }
            }()
            """#
        }
    }

    // MARK: Multiple format params on different segments

    @Test func multipleSegmentsWithDifferentFormats() {
        assertMacro {
            """
            #log(.info, "id: \\(id, format: .hex, privacy: .public) name: \\(name, privacy: .private) rate: \\(rate, format: .fixed(precision: 1))")
            """
        } expansion: {
            #"""
            {
                if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                    Self.logger.info("id: \(id, format: .hex, privacy: .public) name: \(name, privacy: .private) rate: \(rate, format: .fixed(precision: 1))")
                } else {
                    os_log(.info, log: Self._osLog, "id: %{public}@ name: %{private}@ rate: %{public}@", "\(id)", "\(name)", "\(rate)")
                }
            }()
            """#
        }
    }
}
