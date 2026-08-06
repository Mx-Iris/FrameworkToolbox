#if canImport(os)

// `os` and the standard library only. `@Loggable` deliberately has no
// bundle-identifier default — an unspecified subsystem is just the type name —
// so nothing here needs Foundation, and neither does anything the macro
// expands into the caller's file.
import os.log

// MARK: - Caches

// Keyed by runtime metatype identity — used by `@Loggable` on protocols, where
// every conforming type needs its own logger.
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private var loggerByObjectIdentifier = Mutex<[ObjectIdentifier: os.Logger]>([:])

private var osLogByObjectIdentifier = Mutex<[ObjectIdentifier: OSLog]>([:])

private struct SubsystemCategoryCacheKey: Hashable {
    let subsystem: String
    let category: String
}

// Keyed by the subsystem/category pair — used by the `logger(for:)` accessors,
// so that every call site logging to one category shares a single logger no
// matter which type it logs from.
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private var loggerBySubsystemAndCategory = Mutex<[SubsystemCategoryCacheKey: os.Logger]>([:])

private var osLogBySubsystemAndCategory = Mutex<[SubsystemCategoryCacheKey: OSLog]>([:])

// MARK: - Logger caches

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

#endif
