#if canImport(os)

// `os` and the standard library only, for the same reason the rest of this
// target keeps off Foundation: the names here are reached by code the macros
// expand into the caller's file, and that file may not have imported Foundation.
import os.log

// MARK: - Switch storage

// Deliberately plain `Bool`s rather than `Mutex`-guarded state. Every `#log` and
// `#signpost` call site reads them, a single-byte load cannot tear on any Apple
// platform, and paying for an `os_unfair_lock` on that path would buy nothing.
//
// The trade-off is that flipping a switch carries no ordering guarantee against
// concurrent logging — a call already in flight may still emit. These switches
// are meant to be set early at launch, from a debug menu, or from a debugger,
// where that is not a distinction anyone can observe.
nonisolated(unsafe) private var isLoggingGloballyEnabled = true
nonisolated(unsafe) private var isSignpostingGloballyEnabled = true

// The fast path reads these instead of taking the lock below. They stay `false`
// until something is actually disabled by category, so a program that never
// touches the per-category switches never pays for a lock or a set lookup.
nonisolated(unsafe) private var hasDisabledLogCategories = false
nonisolated(unsafe) private var hasDisabledSignpostCategories = false

private let disabledLogCategoryNames = Mutex<Set<String>>([])
private let disabledSignpostCategoryNames = Mutex<Set<String>>([])

// MARK: - LoggingControl

/// Runtime switches for everything `@Loggable` generates.
///
/// Three switches decide whether a given `#log` call emits, and all three must
/// be on:
///
/// 1. the `isEnabled:` argument of `@Loggable` on the type,
/// 2. ``isEnabled`` here, the process-wide switch,
/// 3. ``isEnabled(for:)`` for the category the call site logs to.
///
/// Turning any of them off swaps the generated log handle for `OSLog.disabled`
/// / `Logger.disabled`. That is not "still runs but discards": the `os` module
/// checks the handle *before* evaluating a message's interpolation arguments —
/// they are `@autoclosure` — so `#log(.debug, "\(self.expensiveDescription)")`
/// does not call `expensiveDescription` at all while logging is off.
///
/// A type annotated `@Loggable(isEnabled: false)` is the exception: that one is
/// a compile-time constant, so the switches here cannot turn it back on.
///
/// ## Reaching the default category of a type
///
/// `@Loggable` with no `category:` argument uses the type's own name, so the
/// per-category switch doubles as a per-type one that needs no recompile:
///
///     LoggingControl.setEnabled(false, for: LogCategory("SyncService"))
public enum LoggingControl {

    /// The process-wide logging switch. Defaults to `true`.
    ///
    /// Turning it off silences every `@Loggable` type at once, including call
    /// sites that reach `logger` / `_osLog` by hand rather than through `#log`.
    public static var isEnabled: Bool {
        get { isLoggingGloballyEnabled }
        set { isLoggingGloballyEnabled = newValue }
    }

    /// Turns logging to one category on or off. Every category starts enabled.
    public static func setEnabled(_ isEnabled: Bool, for category: LogCategory) {
        disabledLogCategoryNames.withLock { categoryNames in
            if isEnabled {
                categoryNames.remove(category.name)
            } else {
                categoryNames.insert(category.name)
            }
            hasDisabledLogCategories = !categoryNames.isEmpty
        }
    }

    /// Whether logging to `category` is currently on, ignoring ``isEnabled``
    /// and whatever the type was annotated with.
    public static func isEnabled(for category: LogCategory) -> Bool {
        guard hasDisabledLogCategories else { return true }
        return !disabledLogCategoryNames.withLock { $0.contains(category.name) }
    }

    /// Re-enables every category disabled through ``setEnabled(_:for:)``,
    /// leaving ``isEnabled`` untouched.
    public static func enableAllCategories() {
        disabledLogCategoryNames.withLock { categoryNames in
            categoryNames.removeAll()
            hasDisabledLogCategories = false
        }
    }
}

// MARK: - SignpostingControl

/// Runtime switches for everything `@Signpostable` generates — the signpost
/// counterpart of ``LoggingControl``, with the same three-switch model.
///
/// Kept separate from ``LoggingControl`` rather than folded into one switch
/// because "logs on, instrumentation off" and the reverse are both things
/// people actually want; one shared switch would force a choice between them.
///
/// An interval's fate is decided when it begins. `#signpost(.begin, …)` stores
/// the handle it emitted through in the returned ``SignpostInterval`` and
/// `#signpost(.end, …)` uses that stored handle, so disabling signposting
/// midway through an interval still lets the interval close — no dangling
/// begin, and no end without a begin.
public enum SignpostingControl {

    /// The process-wide signposting switch. Defaults to `true`.
    public static var isEnabled: Bool {
        get { isSignpostingGloballyEnabled }
        set { isSignpostingGloballyEnabled = newValue }
    }

    /// Turns signposting to one category on or off. Every category starts enabled.
    public static func setEnabled(_ isEnabled: Bool, for category: LogCategory) {
        disabledSignpostCategoryNames.withLock { categoryNames in
            if isEnabled {
                categoryNames.remove(category.name)
            } else {
                categoryNames.insert(category.name)
            }
            hasDisabledSignpostCategories = !categoryNames.isEmpty
        }
    }

    /// Whether signposting to `category` is currently on, ignoring ``isEnabled``
    /// and whatever the type was annotated with.
    public static func isEnabled(for category: LogCategory) -> Bool {
        guard hasDisabledSignpostCategories else { return true }
        return !disabledSignpostCategoryNames.withLock { $0.contains(category.name) }
    }

    /// Re-enables every category disabled through ``setEnabled(_:for:)``,
    /// leaving ``isEnabled`` untouched.
    public static func enableAllCategories() {
        disabledSignpostCategoryNames.withLock { categoryNames in
            categoryNames.removeAll()
            hasDisabledSignpostCategories = false
        }
    }
}

// MARK: - The entry points generated code calls

extension LoggableMacro {
    /// Resolves the two runtime switches for one `@Loggable` call site.
    ///
    /// Named by `@Loggable`'s expansion, never called directly.
    ///
    /// `category` is an `@autoclosure` on purpose: on the protocol branch it is
    /// `String(describing: self)`, which is not free, and neither of the two
    /// fast paths below needs the string at all.
    public static func _isEnabled(category: @autoclosure () -> String) -> Bool {
        guard isLoggingGloballyEnabled else { return false }
        guard hasDisabledLogCategories else { return true }
        return !disabledLogCategoryNames.withLock { $0.contains(category()) }
    }
}

extension SignpostableMacro {
    /// Resolves the two runtime switches for one `@Signpostable` call site.
    ///
    /// Named by `@Signpostable`'s expansion, never called directly.
    public static func _isEnabled(category: @autoclosure () -> String) -> Bool {
        guard isSignpostingGloballyEnabled else { return false }
        guard hasDisabledSignpostCategories else { return true }
        return !disabledSignpostCategoryNames.withLock { $0.contains(category()) }
    }
}

#endif
