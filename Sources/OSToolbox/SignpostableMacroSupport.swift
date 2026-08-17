#if canImport(os)

// `os` and the standard library only, for the same reason `@Loggable` keeps off
// Foundation: everything in here is named by code the macros expand into the
// caller's file, and that file may not have imported Foundation.
import os.log
import os.signpost

// MARK: - SignpostableMacro (Namespace)

/// Namespace for the compile-time types and runtime helpers used by the
/// `@Signpostable` and `#signpost` macros.
///
/// The nested marker types below are what the `#signpost` overloads select on.
/// They exist as three separate types rather than three cases of one enum
/// because the overloads differ in *return* type — `.begin` yields a
/// ``SignpostInterval`` while `.event` and `.end` yield `Void` — and overload
/// resolution can only tell them apart if the first argument's type does.
public enum SignpostableMacro {

    /// Selects the `#signpost` overloads that emit a standalone signpost.
    public struct EventType: Sendable {
        public static let event = EventType()
    }

    /// Selects the `#signpost` overload that opens an interval.
    public struct BeginType: Sendable {
        public static let begin = BeginType()
    }

    /// Selects the `#signpost` overloads that close an interval.
    public struct EndType: Sendable {
        public static let end = EndType()
    }
}

// MARK: - Caches

private struct SignpostSubsystemCategoryCacheKey: Hashable {
    let subsystem: String
    let category: String
}

// Keyed by the runtime metatype — used by `@Signpostable` on protocols, where
// every conforming type needs its own signposter.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private var signposterByObjectIdentifier = Mutex<[ObjectIdentifier: os.OSSignposter]>([:])

// Keyed by the subsystem/category pair — used by the `signposter(for:)` accessor,
// so every call site signposting to one category shares a single signposter.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private var signposterBySubsystemAndCategory = Mutex<[SignpostSubsystemCategoryCacheKey: os.OSSignposter]>([:])

// MARK: - Runtime helpers

extension SignpostableMacro {

    /// Runtime helper invoked by `@Signpostable`-generated code on protocols.
    ///
    /// Returns a cached `OSLog` keyed by the runtime type's identity, so each
    /// conforming type signposts under its own subsystem/category.
    ///
    /// Forwards to ``LoggableMacro/_sharedOSLog(for:subsystem:category:)``:
    /// a signpost log handle *is* a log handle, and one subsystem/category pair
    /// should resolve to one `OSLog` whether it was reached through `@Loggable`
    /// or `@Signpostable`.
    public static func _sharedSignpostLog(
        for type: Any.Type,
        subsystem: @autoclosure () -> String,
        category: @autoclosure () -> String
    ) -> os.OSLog {
        LoggableMacro._sharedOSLog(for: type, subsystem: subsystem(), category: category())
    }

    /// Runtime helper invoked by the `_signpostLog(for:)` accessor that
    /// `@Signpostable` generates on every annotated type.
    public static func _sharedSignpostLog(
        subsystem: @autoclosure () -> String,
        category: String
    ) -> os.OSLog {
        LoggableMacro._sharedOSLog(subsystem: subsystem(), category: category)
    }

    /// Runtime helper invoked by `@Signpostable`-generated code on protocols.
    ///
    /// Returns a cached `OSSignposter` keyed by the runtime type's identity.
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public static func _sharedSignposter(
        for type: Any.Type,
        subsystem: @autoclosure () -> String,
        category: @autoclosure () -> String
    ) -> os.OSSignposter {
        let objectIdentifier = ObjectIdentifier(type)
        if let signposter = signposterByObjectIdentifier.withLock({ $0[objectIdentifier] }) {
            return signposter
        }
        // Built on the cached log handle, never through
        // `OSSignposter(subsystem:category:)` — see the note on the
        // subsystem/category overload below.
        let signposter = os.OSSignposter(
            logHandle: _sharedSignpostLog(for: type, subsystem: subsystem(), category: category())
        )
        signposterByObjectIdentifier.withLock {
            $0[objectIdentifier] = signposter
        }
        return signposter
    }

    /// Runtime helper invoked by the `signposter(for:)` accessor that
    /// `@Signpostable` generates on every annotated type.
    ///
    /// Returns a cached `OSSignposter` keyed by the subsystem/category pair, so
    /// every call site signposting to the same category reuses one signposter
    /// regardless of which type it signposts from.
    ///
    /// Deliberately built as `OSSignposter(logHandle:)` over the log handle from
    /// ``_sharedSignpostLog(subsystem:category:)``, never as
    /// `OSSignposter(subsystem:category:)`. That initializer creates a log handle
    /// of its own, which would leave the signposter and `_signpostLog(for:)`
    /// sitting on two different handles for one subsystem/category pair. The
    /// system pairs a begin with an end by handle, so an interval begun through
    /// one and ended through the other would never match up.
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public static func _sharedSignposter(
        subsystem: @autoclosure () -> String,
        category: String
    ) -> os.OSSignposter {
        let cacheKey = SignpostSubsystemCategoryCacheKey(subsystem: subsystem(), category: category)
        if let signposter = signposterBySubsystemAndCategory.withLock({ $0[cacheKey] }) {
            return signposter
        }
        let signposter = os.OSSignposter(
            logHandle: _sharedSignpostLog(subsystem: cacheKey.subsystem, category: cacheKey.category)
        )
        signposterBySubsystemAndCategory.withLock {
            $0[cacheKey] = signposter
        }
        return signposter
    }
}

#endif
