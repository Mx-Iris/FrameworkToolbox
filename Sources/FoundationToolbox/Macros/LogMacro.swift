#if canImport(os)

/// Log level used by the `#log` macro.
///
/// These mirror `OSLogType` values but are available on all OS versions.
public enum LogLevel {
    /// Debug-level messages (maps to `OSLogType.debug` / swift-log `.debug`)
    case debug
    /// Informational messages (maps to `OSLogType.info` / swift-log `.info`)
    case info
    /// Default-level messages (maps to `OSLogType.default` / swift-log `.notice`)
    case `default`
    /// Error-level messages (maps to `OSLogType.error` / swift-log `.error`)
    case error
    /// Fault-level messages (maps to `OSLogType.fault` / swift-log `.critical`)
    case fault
}

// MARK: - LogPrivacy

/// Privacy level for log message interpolation segments.
///
/// Mirrors `os.OSLogPrivacy` but available on all OS versions.
/// Used only for compile-time type checking by the `#log` macro.
public struct LogPrivacy {
    /// Automatically determine the privacy level.
    public static let auto = LogPrivacy()
    /// Mark the interpolated value as public (visible in logs).
    public static let `public` = LogPrivacy()
    /// Mark the interpolated value as private (redacted in logs).
    public static let `private` = LogPrivacy()
    /// Mark the interpolated value as sensitive (redacted in logs).
    public static let sensitive = LogPrivacy()

    /// Mark the interpolated value as private with a mask.
    public static func `private`(mask: Mask) -> LogPrivacy { LogPrivacy() }
    /// Mark the interpolated value as sensitive with a mask.
    public static func sensitive(mask: Mask) -> LogPrivacy { LogPrivacy() }
    /// Automatically determine the privacy level with a mask.
    public static func auto(mask: Mask) -> LogPrivacy { LogPrivacy() }

    public enum Mask {
        case hash
        case none
    }
}

// MARK: - LogMessage

/// A string interpolation type used by the `#log` macro.
///
/// Mirrors `OSLogMessage` string interpolation API surface so that the IDE
/// provides autocomplete for `privacy:`, `align:`, and `format:` parameters.
/// The actual type is never evaluated at runtime — the macro replaces everything at compile time.
public struct LogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {}
    public init(stringInterpolation: StringInterpolation) {}

    public struct StringInterpolation: StringInterpolationProtocol {
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) {}

        // MARK: Generic value (CustomStringConvertible)

        @_disfavoredOverload
        public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: @autoclosure @escaping () -> T, privacy: LogPrivacy = .auto) {}

        // MARK: String

        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> String, privacy: LogPrivacy = .auto) {}

        // MARK: FixedWidthInteger

        public mutating func appendInterpolation<T: FixedWidthInteger>(_ value: @autoclosure @escaping () -> T, privacy: LogPrivacy = .auto) {}

        // MARK: Float / Double

        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> Float, privacy: LogPrivacy = .auto) {}
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> Double, privacy: LogPrivacy = .auto) {}

        // MARK: Bool

        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> Bool, privacy: LogPrivacy = .auto) {}

        // MARK: Error

        @_disfavoredOverload
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> any Error, privacy: LogPrivacy = .auto) {}

        // MARK: Optional Error

        @_disfavoredOverload
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> (any Error)?, privacy: LogPrivacy = .auto) {}

        // MARK: Any.Type

        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> any Any.Type, privacy: LogPrivacy = .auto) {}
    }
}

/// A freestanding expression macro that generates version-checked logging calls.
///
/// On macOS 11.0+ (iOS 14.0+, watchOS 7.0+, tvOS 14.0+), uses `os.Logger`.
/// On older OS versions, falls back to `swift-log`.
///
/// Example:
///
///     #log(.debug, "Processing \(value, privacy: .public)")
///
///     // Expands to:
///     // {
///     //     if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
///     //         Self.logger.debug("Processing \(value, privacy: .public)")
///     //     } else {
///     //         Self._loggableSwiftLogger.debug("Processing \(value)")
///     //     }
///     // }()
@freestanding(expression)
public macro log(_ level: LogLevel, _ message: LogMessage) -> Void = #externalMacro(module: "FoundationToolboxMacros", type: "LogMacro")

#endif
