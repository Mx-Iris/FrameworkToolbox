#if canImport(os)

import os.signpost

/// A token identifying one in-flight signposted interval, returned by
/// `#signpost(.begin, …)` and consumed by `#signpost(.end, …)`.
///
/// This type exists because the two signpost APIs disagree on what a caller has
/// to hold onto between the begin and the end of an interval:
///
/// - `OSSignposter` (macOS 12, iOS 15, watchOS 8, tvOS 15) hands back an
///   ``os/OSSignpostIntervalState`` object and wants it back at `endInterval`.
/// - `os_signpost` (macOS 10.14 and up, so every version this package supports)
///   hands back nothing; the caller keeps the `OSSignpostID` it passed in.
///
/// Neither is usable as the type of a stored property on this package's
/// deployment floor: `OSSignpostIntervalState` is gated at macOS 12, so a
/// property declared with that type would not compile for macOS 10.15. This
/// token carries whichever of the two the running OS produced, and exposes the
/// gated one only from behind an `@available` accessor — the same shape as the
/// `Any?`-backed storage that `@AvailableNonMutating` generates.
///
/// It also carries the interval's `name` and the `OSLog` it began on, which is
/// what makes `#signpost(.end, …)` self-contained — it needs nothing from the
/// enclosing type, so an interval may be ended anywhere the token reaches. Both
/// matter for correctness rather than convenience:
///
/// - `OSSignposter.endInterval` asserts at runtime that the name matches the one
///   the interval began with.
/// - The system pairs a begin with an end by log handle, name and signpost ID.
///   Re-deriving the handle at the end from a subsystem/category pair would not
///   do: `OSLog(subsystem:category:)` hands back a fresh object each call, and
///   nothing promises two of them share one underlying handle. Carrying the
///   original reference removes the question.
public struct SignpostInterval: Sendable {
    /// The interval name, as passed to `#signpost(.begin, …)`.
    public let name: StaticString

    /// The identifier disambiguating this interval from others sharing its name.
    public let signpostID: os.OSSignpostID

    /// The log handle this interval began on. `#signpost(.end, …)` closes the
    /// interval on this very handle.
    public let log: os.OSLog

    /// The `OSSignpostIntervalState` this interval began with, or `nil` when the
    /// interval was begun through the `os_signpost` path.
    ///
    /// Typed `(any Sendable)?` rather than `AnyObject?`: `OSSignpostIntervalState`
    /// is declared `@unchecked Sendable`, so carrying it as `any Sendable` keeps
    /// this struct's own `Sendable` conformance checkable instead of forcing an
    /// `@unchecked` escape hatch onto it.
    private let intervalState: (any Sendable)?

    public init(
        name: StaticString,
        signpostID: os.OSSignpostID,
        log: os.OSLog,
        intervalState: (any Sendable)?
    ) {
        self.name = name
        self.signpostID = signpostID
        self.log = log
        self.intervalState = intervalState
    }

    /// The interval state to pass to `OSSignposter.endInterval`.
    ///
    /// Reconstructs the state from ``signpostID`` when this token carries none —
    /// which covers a token that crossed a process boundary, and is the same
    /// recovery path Apple documents for callers that no longer hold the state
    /// returned by `beginInterval`.
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public var osSignpostIntervalState: os.OSSignpostIntervalState {
        if let intervalState = intervalState as? os.OSSignpostIntervalState {
            return intervalState
        }
        return os.OSSignpostIntervalState.beginState(id: signpostID)
    }
}

#endif
