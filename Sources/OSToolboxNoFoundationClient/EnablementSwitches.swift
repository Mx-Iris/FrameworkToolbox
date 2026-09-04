import OSToolbox

// Compile-time guard for the `isEnabled:` switch on `@Loggable` /
// `@Signpostable`, in every shape it can take. Two claims are being pinned:
//
//   1. All three forms compile — omitted, a boolean literal, and an arbitrary
//      expression — on concrete types, generic ones, and protocols.
//   2. None of them reaches Foundation from the expansion (this target may not
//      import it; see `main.swift`).
//
// What the switch *does* at runtime is covered by `LoggingControlTests`; what it
// expands to is covered by the snapshot tests. This file only asserts that the
// generated code is well-formed in the caller's file.

// A flag of the caller's own, which is the shape the expression form exists for:
// "off in normal builds, on while I am testing this feature."
enum DiagnosticFlags {
    static let verboseLogging = false

    // Deliberately mutable, to confirm the expression form re-reads it per call
    // site rather than snapshotting it into a `static let`.
    nonisolated(unsafe) static var performanceTracing = false
}

// MARK: - Statically off

@Loggable(isEnabled: false)
struct SilentService {
    func emit() {
        #log(.debug, "compiles, never emits")
        #log(.error, category: .startup, "categorised, also never emits")
    }
}

@Signpostable(isEnabled: false)
struct UnmeasuredService {
    func emit() {
        #signpost(.event, "compiles, never emits")
    }

    func measure() -> Int {
        #signpostInterval("also-never-emits") {
            42
        }
    }
}

@Loggable(isEnabled: false)
@Signpostable(isEnabled: false)
final class FullySilentService {
    func emit() {
        #log(.debug, "both macros off on one type")
        #signpost(.event, "both-off")
    }
}

// Statically off inside a generic context: no `static let` is emitted either
// way, so this is the one combination where the two branches coincide.
@Loggable(isEnabled: false)
struct SilentGenericService<Element> {
    func emit() {
        #log(.debug, "generic and statically off")
    }
}

// MARK: - Gated on the caller's own flag

@Loggable(isEnabled: DiagnosticFlags.verboseLogging)
struct ConditionallyLoggingService {
    func emit() {
        #log(.debug, "emits only while the flag is on")
    }
}

@Signpostable(isEnabled: DiagnosticFlags.performanceTracing)
struct ConditionallyMeasuredService {
    func measure() -> Int {
        #signpostInterval("gated-interval") {
            7
        }
    }
}

// The expression is transplanted verbatim, so a compound one works as well as a
// bare reference.
@Loggable(isEnabled: DiagnosticFlags.verboseLogging || DiagnosticFlags.performanceTracing)
struct EitherFlagService {
    func emit() {
        #log(.debug, "gated on two flags")
    }
}

@Loggable(isEnabled: DiagnosticFlags.verboseLogging)
struct ConditionallyLoggingGenericService<Element> {
    func emit() {
        #log(.debug, "generic and flag-gated")
    }
}

// MARK: - Explicit `true`, and combinations with the other arguments

@Loggable(isEnabled: true)
struct ExplicitlyEnabledService {
    func emit() {
        #log(.debug, "same expansion as omitting the argument")
    }
}

@Loggable(.internal, isEnabled: false, subsystem: "com.example.guard", category: "Silenced")
struct SilentCustomisedService {
    func emit() {
        #log(.debug, "access level, subsystem and category alongside the switch")
    }
}

@Signpostable(.public, isEnabled: DiagnosticFlags.performanceTracing, subsystem: "com.example.guard")
public struct PublicConditionallyMeasuredService {
    public init() {}

    public func emit() {
        #signpost(.event, "public, gated")
    }
}

// MARK: - Protocols

// The switch resolves inside the default implementations, so it adds no protocol
// requirement and conforming types need no change.

@Loggable(isEnabled: false)
protocol SilentlyLogging {}

struct ConformsToSilentlyLogging: SilentlyLogging {
    func emit() {
        #log(.debug, "protocol default implementations, statically off")
    }
}

@Loggable(isEnabled: DiagnosticFlags.verboseLogging)
protocol ConditionallyLogging {}

struct ConformsToConditionallyLogging: ConditionallyLogging {
    func emit() {
        #log(.debug, "protocol default implementations, flag-gated")
    }
}

@Loggable(asProtocolRequirement: false, isEnabled: false)
protocol FrozenSilentlyLogging {}

struct ConformsToFrozenSilentlyLogging: FrozenSilentlyLogging {
    func emit() {
        #log(.debug, "frozen protocol defaults, statically off")
    }
}
