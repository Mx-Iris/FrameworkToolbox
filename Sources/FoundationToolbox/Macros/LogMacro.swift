#if canImport(os)

import Foundation

// MARK: - LoggableMacro (Namespace)

/// Namespace for compile-time types used by the `@Loggable` and `#log` macros.
///
/// All nested types mirror their `os` module counterparts (e.g. ``OSLogType``,
/// ``OSLogPrivacy``, ``OSLogFloatFormatting``) under this namespace to avoid
/// conflicts with the system definitions.
public enum LoggableMacro {

    // MARK: - OSLogType

    /// Log level used by the `#log` macro.
    ///
    /// Mirrors `os.OSLogType` but available on all OS versions.
    public enum OSLogType {
        case debug
        case info
        case `default`
        case error
        case fault
    }

    // MARK: - OSLogPrivacy

    /// Privacy level for log message interpolation segments.
    ///
    /// Mirrors `os.OSLogPrivacy` but available on all OS versions.
    public struct OSLogPrivacy {
        public static let auto = OSLogPrivacy()
        public static let `public` = OSLogPrivacy()
        public static let `private` = OSLogPrivacy()
        public static let sensitive = OSLogPrivacy()

        public static func `private`(mask: Mask) -> OSLogPrivacy { OSLogPrivacy() }
        public static func sensitive(mask: Mask) -> OSLogPrivacy { OSLogPrivacy() }
        public static func auto(mask: Mask) -> OSLogPrivacy { OSLogPrivacy() }

        public enum Mask {
            case hash
            case none
        }
    }

    // MARK: - OSLogFloatFormatting

    /// Formatting options for floating-point log interpolations.
    ///
    /// Mirrors `os.OSLogFloatFormatting`.
    public struct OSLogFloatFormatting {
        public static var fixed: OSLogFloatFormatting { OSLogFloatFormatting() }
        public static func fixed(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting { OSLogFloatFormatting() }
        public static func fixed(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting { OSLogFloatFormatting() }

        public static var hex: OSLogFloatFormatting { OSLogFloatFormatting() }
        public static func hex(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting { OSLogFloatFormatting() }

        public static var exponential: OSLogFloatFormatting { OSLogFloatFormatting() }
        public static func exponential(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting { OSLogFloatFormatting() }
        public static func exponential(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting { OSLogFloatFormatting() }

        public static var hybrid: OSLogFloatFormatting { OSLogFloatFormatting() }
        public static func hybrid(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting { OSLogFloatFormatting() }
        public static func hybrid(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting { OSLogFloatFormatting() }
    }

    // MARK: - OSLogIntegerFormatting

    /// Formatting options for integer log interpolations.
    ///
    /// Mirrors `os.OSLogIntegerFormatting`.
    public struct OSLogIntegerFormatting {
        public static var decimal: OSLogIntegerFormatting { OSLogIntegerFormatting() }
        public static func decimal(explicitPositiveSign: Bool = false, minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting { OSLogIntegerFormatting() }
        public static func decimal(explicitPositiveSign: Bool = false) -> OSLogIntegerFormatting { OSLogIntegerFormatting() }

        public static var hex: OSLogIntegerFormatting { OSLogIntegerFormatting() }
        public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false, minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting { OSLogIntegerFormatting() }
        public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting { OSLogIntegerFormatting() }

        public static var octal: OSLogIntegerFormatting { OSLogIntegerFormatting() }
        public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false, minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting { OSLogIntegerFormatting() }
        public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting { OSLogIntegerFormatting() }
    }

    // MARK: - OSLogStringAlignment

    /// Alignment options for string log interpolations.
    ///
    /// Mirrors `os.OSLogStringAlignment`.
    public struct OSLogStringAlignment {
        public static var none: OSLogStringAlignment { OSLogStringAlignment() }
        public static func right(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment { OSLogStringAlignment() }
        public static func left(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment { OSLogStringAlignment() }
    }

    // MARK: - OSLogBoolFormat

    /// Formatting options for boolean log interpolations.
    ///
    /// Mirrors `os.OSLogBoolFormat`.
    public enum OSLogBoolFormat {
        case truth
        case answer
    }

    // MARK: - OSLogPointerFormat

    /// Formatting options for pointer log interpolations.
    ///
    /// Mirrors `os.OSLogPointerFormat`.
    public enum OSLogPointerFormat {
        case ipv6Address
        case timeval
        case timespec
        case uuid
        case sockaddr
        case none
    }

    // MARK: - OSLogInt32ExtendedFormat

    /// Extended formatting options for `Int32` log interpolations.
    ///
    /// Mirrors `os.OSLogInt32ExtendedFormat`.
    public enum OSLogInt32ExtendedFormat {
        case ipv4Address
        case secondsSince1970
        case darwinErrno
        case darwinMode
        case darwinSignal
        case machErrno
        case bitrate
        case bitrateIEC
        case byteCount
        case byteCountIEC
        case truth
        case answer
    }

    // MARK: - OSLogIntExtendedFormat

    /// Extended formatting options for `Int` log interpolations.
    ///
    /// Mirrors `os.OSLogIntExtendedFormat`.
    public enum OSLogIntExtendedFormat {
        case bitrate
        case bitrateIEC
        case byteCount
        case byteCountIEC
        case secondsSince1970
    }

    // MARK: - OSLogMessage

    /// A string interpolation type used by the `#log` macro.
    ///
    /// Mirrors `OSLogMessage` string interpolation API surface so that the IDE
    /// provides autocomplete for `privacy:`, `align:`, and `format:` parameters.
    /// The actual type is never evaluated at runtime — the macro replaces everything at compile time.
    public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
        public init(stringLiteral value: String) {}
        public init(stringInterpolation: StringInterpolation) {}

        public struct StringInterpolation: StringInterpolationProtocol {
            public init(literalCapacity: Int, interpolationCount: Int) {}
            public mutating func appendLiteral(_ literal: String) {}

            // MARK: Float

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Float, format: OSLogFloatFormatting = .fixed, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Double

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Double, format: OSLogFloatFormatting = .fixed, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Int

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Int8

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int8, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Int16

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int16, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Int32

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int32, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Int64

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int64, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: UInt

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: UInt8

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt8, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: UInt16

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt16, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: UInt32

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt32, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: UInt64

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt64, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Int32 (extended format)

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int32, format: OSLogInt32ExtendedFormat, privacy: OSLogPrivacy = .auto) {}

            // MARK: Int (extended format)

            public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int, format: OSLogIntExtendedFormat, privacy: OSLogPrivacy = .auto) {}

            // MARK: String

            public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> String, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Bool

            public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> Bool, format: OSLogBoolFormat = .truth, privacy: OSLogPrivacy = .auto) {}

            // MARK: NSObject

            public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> NSObject, privacy: OSLogPrivacy = .auto) {}

            // MARK: NSObject?

            public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> NSObject?, privacy: OSLogPrivacy = .auto) {}

            // MARK: UnsafeRawBufferPointer

            public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawBufferPointer, format: OSLogPointerFormat = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: UnsafeRawPointer

            public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawPointer, bytes: @autoclosure @escaping () -> Int, format: OSLogPointerFormat = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: CustomStringConvertible

            @_disfavoredOverload
            public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: @autoclosure @escaping () -> T, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Any.Type

            public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> any Any.Type, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {}

            // MARK: Error

            @_disfavoredOverload
            public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> any Error, privacy: OSLogPrivacy = .auto) {}

            // MARK: Error?

            @_disfavoredOverload
            public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> (any Error)?, privacy: OSLogPrivacy = .auto) {}
        }
    }
}

/// A freestanding expression macro that generates version-checked logging calls.
///
/// On macOS 11.0+ (iOS 14.0+, watchOS 7.0+, tvOS 14.0+), uses `os.Logger`.
/// On older OS versions, falls back to the legacy `os_log` API.
///
/// Example:
///
///     #log(.debug, "Processing \(value, privacy: .public) with \(secret, privacy: .private)")
///
///     // Expands to:
///     // {
///     //     if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
///     //         Self.logger.debug("Processing \(value, privacy: .public) with \(secret, privacy: .private)")
///     //     } else {
///     //         os_log(.debug, log: Self._osLog, "Processing %{public}@ with %{private}@", "\(value)", "\(secret)")
///     //     }
///     // }()
@freestanding(expression)
public macro log(_ level: LoggableMacro.OSLogType, _ message: LoggableMacro.OSLogMessage) -> Void = #externalMacro(module: "FoundationToolboxMacros", type: "LogMacro")

#endif
