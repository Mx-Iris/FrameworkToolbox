#if canImport(os)

import os.log
import os.signpost

/// Emits a standalone signpost marking a point in time.
///
/// The signpost counterpart of `#log`: it expands to a version-checked call that
/// uses `OSSignposter` on macOS 12 / iOS 15 / watchOS 8 / tvOS 15 and up, and
/// falls back to `os_signpost` below that. Requires the enclosing type to be
/// annotated with `@Signpostable`.
///
///     #signpost(.event, "tapped")
///     #signpost(.event, "tapped", "index=\(index, privacy: .public)")
///     #signpost(.event, category: .pointsOfInterest, "tapped")
///
/// Expands to:
///
///     // {
///     //     if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
///     //         Self.signposter.emitEvent("tapped", id: .exclusive, "index=\(index, privacy: .public)")
///     //     } else {
///     //         "\(index)".withCString { legacyArgument0 in
///     //             os_signpost(.event, log: Self._signpostLog, name: "tapped", signpostID: .exclusive, "index=%{public}s", legacyArgument0)
///     //         }
///     //     }
///     // }()
///
/// - Parameters:
///   - type: Always `.event` for this overload.
///   - category: Emit under a specific ``LogCategory`` instead of the enclosing
///     type's default. Pass `.pointsOfInterest` to land on Instruments' default
///     track.
///   - name: The signpost name. Must be a literal — it names the signpost in
///     Instruments, and the system requires a `StaticString`.
///   - id: A signpost identifier, defaulting to `.exclusive`. Pass one to tie an
///     event to a specific interval.
@freestanding(expression)
public macro signpost(
    _ type: SignpostableMacro.EventType,
    category: LogCategory? = nil,
    _ name: StaticString,
    id: os.OSSignpostID? = nil
) -> Void = #externalMacro(module: "OSToolboxMacros", type: "SignpostMacro")

/// Overload of `#signpost(.event, …)` that attaches a message.
///
/// The message is a string interpolation with the same `privacy:`, `align:` and
/// `format:` options as `#log`. It has to be spelled at the call site rather than
/// passed in through a helper, because the system's signpost message type is
/// constant-evaluated at compile time.
@freestanding(expression)
public macro signpost(
    _ type: SignpostableMacro.EventType,
    category: LogCategory? = nil,
    _ name: StaticString,
    _ message: LoggableMacro.OSLogMessage,
    id: os.OSSignpostID? = nil
) -> Void = #externalMacro(module: "OSToolboxMacros", type: "SignpostMacro")

/// Opens a signposted interval, returning the token that closes it.
///
/// Use this form when the begin and the end cannot sit in one scope — across an
/// async boundary, a delegate callback, or two separate methods. When they *can*,
/// prefer ``signpostInterval(_:around:)``, which cannot be left unclosed.
///
///     private var uploadInterval: SignpostInterval?
///
///     func uploadDidStart() {
///         uploadInterval = #signpost(.begin, "upload", "bytes=\(byteCount)")
///     }
///
///     func uploadDidFinish() {
///         guard let uploadInterval else { return }
///         #signpost(.end, uploadInterval, "ok=\(true, privacy: .public)")
///     }
///
/// The returned ``SignpostInterval`` carries the name, identifier and log handle
/// the interval began on, so `#signpost(.end, …)` needs nothing from the
/// enclosing type and closes the interval on the very handle it began on.
///
/// - Parameters:
///   - type: Always `.begin` for this overload.
///   - category: Begin under a specific ``LogCategory``. The matching end
///     follows the token, so it does not need repeating.
///   - name: The interval name. Must be a literal.
///   - id: A signpost identifier. Defaults to a freshly made one, which is what
///     lets several intervals of the same name be in flight at once. Pass one
///     explicitly to derive it from an object (`makeSignpostID(from:)`).
@freestanding(expression)
public macro signpost(
    _ type: SignpostableMacro.BeginType,
    category: LogCategory? = nil,
    _ name: StaticString,
    id: os.OSSignpostID? = nil
) -> SignpostInterval = #externalMacro(module: "OSToolboxMacros", type: "SignpostMacro")

/// Overload of `#signpost(.begin, …)` that attaches a message.
@freestanding(expression)
public macro signpost(
    _ type: SignpostableMacro.BeginType,
    category: LogCategory? = nil,
    _ name: StaticString,
    _ message: LoggableMacro.OSLogMessage,
    id: os.OSSignpostID? = nil
) -> SignpostInterval = #externalMacro(module: "OSToolboxMacros", type: "SignpostMacro")

/// Closes the signposted interval identified by `interval`.
///
/// Self-contained: the token carries everything needed, so this may be used from
/// anywhere, including a type that is not itself `@Signpostable`.
///
/// One interval must be ended exactly once. `OSSignposter` asserts on a double
/// end — trapping in debug builds, and attaching an error message to the closing
/// signpost in release builds.
@freestanding(expression)
public macro signpost(
    _ type: SignpostableMacro.EndType,
    _ interval: SignpostInterval
) -> Void = #externalMacro(module: "OSToolboxMacros", type: "SignpostMacro")

/// Overload of `#signpost(.end, …)` that attaches a message.
@freestanding(expression)
public macro signpost(
    _ type: SignpostableMacro.EndType,
    _ interval: SignpostInterval,
    _ message: LoggableMacro.OSLogMessage
) -> Void = #externalMacro(module: "OSToolboxMacros", type: "SignpostMacro")

/// Measures `body`, emitting a signposted interval around it.
///
/// The preferred interval form: begin and end are generated as a pair with the
/// end in a `defer`, so the interval closes on every exit path — early `return`,
/// thrown error, cancellation. Requires the enclosing type to be annotated with
/// `@Signpostable`.
///
///     func load() throws -> Data {
///         try #signpostInterval("load") {
///             try readFromDisk()
///         }
///     }
///
/// Works with any body — returning, `Void`, `throws`, `async`, or all of them.
/// The macro never inserts `try` or `await` of its own; the body is spliced in
/// verbatim and the compiler infers the effects, so write them at the call site
/// exactly as the body demands.
///
/// - Parameters:
///   - name: The interval name. Must be a literal.
///   - category: Measure under a specific ``LogCategory``.
///   - id: A signpost identifier. Defaults to a freshly made one.
///   - body: The code to measure. Spliced into the expansion once — not once per
///     OS-version branch.
@freestanding(expression)
public macro signpostInterval<Result>(
    _ name: StaticString,
    category: LogCategory? = nil,
    id: os.OSSignpostID? = nil,
    around body: () throws -> Result
) -> Result = #externalMacro(module: "OSToolboxMacros", type: "SignpostIntervalMacro")

/// Overload of ``signpostInterval(_:category:id:around:)`` accepting an `async`
/// body.
///
/// A macro declaration is type-checked like a function, so an `async` closure
/// cannot be passed to the synchronous overload above even though both expand to
/// the same code — the expansion splices the body in verbatim and lets the
/// compiler infer its effects. A synchronous body still selects the synchronous
/// overload, which needs no conversion.
@freestanding(expression)
public macro signpostInterval<Result>(
    _ name: StaticString,
    category: LogCategory? = nil,
    id: os.OSSignpostID? = nil,
    around body: () async throws -> Result
) -> Result = #externalMacro(module: "OSToolboxMacros", type: "SignpostIntervalMacro")

#endif
