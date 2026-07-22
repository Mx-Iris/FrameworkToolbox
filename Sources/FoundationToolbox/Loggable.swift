#if canImport(os)

import os.log
import Foundation

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public protocol Loggable {
    var logger: os.Logger { get }
    static var logger: os.Logger { get }
    static var subsystem: String { get }
    static var category: String { get }
}

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private var loggerByObjectIdentifier = Mutex<[ObjectIdentifier: os.Logger]>([:])

private var osLogByObjectIdentifier = Mutex<[ObjectIdentifier: OSLog]>([:])

private struct SubsystemCategoryCacheKey: Hashable {
    let subsystem: String
    let category: String
}

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private var loggerBySubsystemAndCategory = Mutex<[SubsystemCategoryCacheKey: os.Logger]>([:])

private var osLogBySubsystemAndCategory = Mutex<[SubsystemCategoryCacheKey: OSLog]>([:])

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension Loggable {
    public static var logger: os.Logger {
        let objectIdentifier = ObjectIdentifier(self)
        if let logger = loggerByObjectIdentifier.withLock({ $0[objectIdentifier] }) {
            return logger
        }

        let logger = os.Logger(subsystem: subsystem, category: category)
        loggerByObjectIdentifier.withLock {
            $0[objectIdentifier] = logger
        }
        return logger
    }

    public var logger: os.Logger { Self.logger }

    public static var category: String {
        .init(describing: self)
    }

    public static var subsystem: String {
        Bundle(for: BundleClass.self).bundleIdentifier ?? .init(describing: self)
    }
}

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension Loggable where Self: AnyObject {
    public static var subsystem: String {
        Bundle(for: self).bundleIdentifier ?? .init(describing: self)
    }
}

// MARK: - Macro runtime support

extension LoggableMacro {
    /// Runtime helper invoked by `@Loggable`-generated code on protocols and extensions.
    ///
    /// Returns a cached `os.Logger` keyed by the runtime type's `ObjectIdentifier`, so
    /// each concrete conforming type gets its own logger lazily without paying the
    /// allocation cost more than once.
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    public static func _sharedLogger(
        for type: Any.Type,
        subsystem: @autoclosure () -> String,
        category: @autoclosure () -> String
    ) -> os.Logger {
        let objectIdentifier = ObjectIdentifier(type)
        if let logger = loggerByObjectIdentifier.withLock({ $0[objectIdentifier] }) {
            return logger
        }
        let logger = os.Logger(subsystem: subsystem(), category: category())
        loggerByObjectIdentifier.withLock {
            $0[objectIdentifier] = logger
        }
        return logger
    }

    /// Runtime helper invoked by `@Loggable`-generated code on protocols and extensions.
    ///
    /// Returns a cached `OSLog` keyed by the runtime type's `ObjectIdentifier`, used by
    /// the legacy fallback path of `#log` on OS versions older than the `os.Logger` minimums.
    public static func _sharedOSLog(
        for type: Any.Type,
        subsystem: @autoclosure () -> String,
        category: @autoclosure () -> String
    ) -> OSLog {
        let objectIdentifier = ObjectIdentifier(type)
        if let osLog = osLogByObjectIdentifier.withLock({ $0[objectIdentifier] }) {
            return osLog
        }
        let osLog = OSLog(subsystem: subsystem(), category: category())
        osLogByObjectIdentifier.withLock {
            $0[objectIdentifier] = osLog
        }
        return osLog
    }

    /// Runtime helper invoked by the `logger(for:)` accessor that `@Loggable`
    /// generates on every annotated type.
    ///
    /// Returns a cached `os.Logger` keyed by the subsystem/category string pair,
    /// so every call site logging to the same category reuses one logger
    /// instance regardless of which type it logs from.
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    public static func _sharedLogger(
        subsystem: @autoclosure () -> String,
        category: String
    ) -> os.Logger {
        let cacheKey = SubsystemCategoryCacheKey(subsystem: subsystem(), category: category)
        if let logger = loggerBySubsystemAndCategory.withLock({ $0[cacheKey] }) {
            return logger
        }
        let logger = os.Logger(subsystem: cacheKey.subsystem, category: cacheKey.category)
        loggerBySubsystemAndCategory.withLock {
            $0[cacheKey] = logger
        }
        return logger
    }

    /// Runtime helper invoked by the `_osLog(for:)` accessor that `@Loggable`
    /// generates on every annotated type, used by the legacy fallback path of
    /// `#log` on OS versions older than the `os.Logger` minimums.
    public static func _sharedOSLog(
        subsystem: @autoclosure () -> String,
        category: String
    ) -> OSLog {
        let cacheKey = SubsystemCategoryCacheKey(subsystem: subsystem(), category: category)
        if let osLog = osLogBySubsystemAndCategory.withLock({ $0[cacheKey] }) {
            return osLog
        }
        let osLog = OSLog(subsystem: cacheKey.subsystem, category: cacheKey.category)
        osLogBySubsystemAndCategory.withLock {
            $0[cacheKey] = osLog
        }
        return osLog
    }
}

private final class BundleClass {}

#endif
