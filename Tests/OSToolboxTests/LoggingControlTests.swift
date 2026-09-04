import Testing
import os

@testable import OSToolbox

// The switches these suites exercise are process-wide, so the suites must not
// run in parallel with themselves — hence `.serialized`. Each test also restores
// what it changed, so ordering between suites does not matter either.

// MARK: - Probes

/// Counts how many times its interpolated value is asked for.
///
/// This is what makes the central claim testable: a disabled handle does not
/// merely discard the message, it never evaluates the message's interpolation
/// arguments, because `os`'s internal `guard logObject.isEnabled(type:)` sits
/// ahead of the argument closures and those closures are `@autoclosure`.
@Loggable(.internal)
struct InterpolationProbe {
    nonisolated(unsafe) static var evaluationCount = 0

    static var trackedValue: Int {
        evaluationCount += 1
        return evaluationCount
    }

    static func resetEvaluationCount() {
        evaluationCount = 0
    }

    /// `.error` rather than `.debug`: debug-level logging is off by default
    /// unless something like `log config` turns it on, which would make the
    /// enabled half of the comparison depend on the machine's configuration.
    func emit() {
        #log(.error, "tracked=\(Self.trackedValue)")
    }

    func emitUnderCategory() {
        #log(.error, category: .probeCategory, "tracked=\(Self.trackedValue)")
    }
}

extension LogCategory {
    static let probeCategory = LogCategory("LoggingControlTests.probe")
    static let otherProbeCategory = LogCategory("LoggingControlTests.other")
}

@Loggable(.internal)
struct RuntimeControlledService {}

@Loggable(.internal, isEnabled: false)
struct StaticallyDisabledService {}

@Loggable(.internal)
struct GenericRuntimeControlledService<Element> {}

@Signpostable(.internal)
struct RuntimeControlledSignpostService {}

@Signpostable(.internal, isEnabled: false)
struct StaticallyDisabledSignpostService {}

// MARK: - LoggingControl

@Suite(.serialized)
struct LoggingControlTests {

    init() {
        LoggingControl.isEnabled = true
        LoggingControl.enableAllCategories()
    }

    @Test func defaultsToEnabled() {
        #expect(LoggingControl.isEnabled)
        #expect(LoggingControl.isEnabled(for: .probeCategory))
        #expect(RuntimeControlledService._osLog !== OSLog.disabled)
    }

    @Test func globalSwitchSwapsInTheDisabledHandle() {
        defer { LoggingControl.isEnabled = true }

        LoggingControl.isEnabled = false
        #expect(RuntimeControlledService._osLog === OSLog.disabled)
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            #expect(RuntimeControlledService.logger.isEnabled(type: .error) == false)
        }

        LoggingControl.isEnabled = true
        #expect(RuntimeControlledService._osLog !== OSLog.disabled)
    }

    /// The generic branch resolves its handle through the runtime cache rather
    /// than a `static let`, so the switch has to reach it by a different path.
    @Test func globalSwitchReachesTheGenericBranch() {
        defer { LoggingControl.isEnabled = true }

        #expect(GenericRuntimeControlledService<Int>._osLog !== OSLog.disabled)
        LoggingControl.isEnabled = false
        #expect(GenericRuntimeControlledService<Int>._osLog === OSLog.disabled)
    }

    @Test func categorySwitchAffectsOnlyItsOwnCategory() {
        defer { LoggingControl.enableAllCategories() }

        LoggingControl.setEnabled(false, for: .probeCategory)
        #expect(LoggingControl.isEnabled(for: .probeCategory) == false)
        #expect(LoggingControl.isEnabled(for: .otherProbeCategory))
        #expect(InterpolationProbe._osLog(for: .probeCategory) === OSLog.disabled)
        #expect(InterpolationProbe._osLog(for: .otherProbeCategory) !== OSLog.disabled)

        LoggingControl.setEnabled(true, for: .probeCategory)
        #expect(InterpolationProbe._osLog(for: .probeCategory) !== OSLog.disabled)
    }

    /// `@Loggable` with no `category:` uses the type's own name, which is what
    /// makes the per-category switch double as a per-type one needing no
    /// recompile.
    @Test func categorySwitchReachesATypesDefaultCategory() {
        defer { LoggingControl.enableAllCategories() }

        LoggingControl.setEnabled(false, for: LogCategory("RuntimeControlledService"))
        #expect(RuntimeControlledService._osLog === OSLog.disabled)
    }

    @Test func enableAllCategoriesClearsEveryOverride() {
        LoggingControl.setEnabled(false, for: .probeCategory)
        LoggingControl.setEnabled(false, for: .otherProbeCategory)

        LoggingControl.enableAllCategories()

        #expect(LoggingControl.isEnabled(for: .probeCategory))
        #expect(LoggingControl.isEnabled(for: .otherProbeCategory))
    }

    /// `enableAllCategories()` must not undo the global switch — they are
    /// separate controls and clearing one should not silently restore the other.
    @Test func enableAllCategoriesLeavesTheGlobalSwitchAlone() {
        defer { LoggingControl.isEnabled = true }

        LoggingControl.isEnabled = false
        LoggingControl.enableAllCategories()
        #expect(LoggingControl.isEnabled == false)
    }

    /// `isEnabled: false` on the type is a compile-time constant, so nothing at
    /// runtime can turn it back on.
    @Test func staticallyDisabledIgnoresTheRuntimeSwitches() {
        #expect(LoggingControl.isEnabled)
        #expect(StaticallyDisabledService._osLog === OSLog.disabled)
        #expect(StaticallyDisabledService._osLog(for: .probeCategory) === OSLog.disabled)
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            #expect(StaticallyDisabledService.logger.isEnabled(type: .error) == false)
        }
    }
}

// MARK: - The interpolation claim

@Suite(.serialized)
struct DisabledLoggingSkipsInterpolationTests {

    init() {
        LoggingControl.isEnabled = true
        LoggingControl.enableAllCategories()
        InterpolationProbe.resetEvaluationCount()
    }

    /// Pins the ordering inside `os`'s `osLogInternal`: the enablement check
    /// comes before the argument closures run. If a future SDK moved it, this
    /// goes red — which is the point, since the whole design of the switch rests
    /// on that ordering.
    @Test func globallyDisabledLoggingEvaluatesNothing() {
        defer { LoggingControl.isEnabled = true }

        // Control group first: with logging on, the value is asked for.
        InterpolationProbe().emit()
        let evaluationsWhileEnabled = InterpolationProbe.evaluationCount
        #expect(
            evaluationsWhileEnabled > 0,
            "error-level logging is expected to be enabled by default; if this fails the machine's log configuration has been changed"
        )

        LoggingControl.isEnabled = false
        InterpolationProbe.resetEvaluationCount()
        InterpolationProbe().emit()
        #expect(InterpolationProbe.evaluationCount == 0)
    }

    @Test func categoryDisabledLoggingEvaluatesNothing() {
        defer { LoggingControl.enableAllCategories() }

        InterpolationProbe().emitUnderCategory()
        #expect(InterpolationProbe.evaluationCount > 0)

        LoggingControl.setEnabled(false, for: .probeCategory)
        InterpolationProbe.resetEvaluationCount()
        InterpolationProbe().emitUnderCategory()
        #expect(InterpolationProbe.evaluationCount == 0)
    }
}

// MARK: - SignpostingControl

@Suite(.serialized)
struct SignpostingControlTests {

    init() {
        SignpostingControl.isEnabled = true
        SignpostingControl.enableAllCategories()
    }

    @Test func defaultsToEnabled() {
        #expect(SignpostingControl.isEnabled)
        #expect(RuntimeControlledSignpostService._signpostLog !== OSLog.disabled)
    }

    @Test func globalSwitchSwapsInTheDisabledHandle() {
        defer { SignpostingControl.isEnabled = true }

        SignpostingControl.isEnabled = false
        #expect(RuntimeControlledSignpostService._signpostLog === OSLog.disabled)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            #expect(RuntimeControlledSignpostService.signposter.isEnabled == false)
        }

        SignpostingControl.isEnabled = true
        #expect(RuntimeControlledSignpostService._signpostLog !== OSLog.disabled)
    }

    @Test func categorySwitchAffectsOnlyItsOwnCategory() {
        defer { SignpostingControl.enableAllCategories() }

        SignpostingControl.setEnabled(false, for: .probeCategory)
        #expect(RuntimeControlledSignpostService._signpostLog(for: .probeCategory) === OSLog.disabled)
        #expect(RuntimeControlledSignpostService._signpostLog(for: .otherProbeCategory) !== OSLog.disabled)
    }

    @Test func staticallyDisabledIgnoresTheRuntimeSwitches() {
        #expect(SignpostingControl.isEnabled)
        #expect(StaticallyDisabledSignpostService._signpostLog === OSLog.disabled)
        if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
            #expect(StaticallyDisabledSignpostService.signposter.isEnabled == false)
        }
    }

    /// The two switches are separate on purpose — "logs on, instrumentation off"
    /// and the reverse are both things people want.
    @Test func loggingAndSignpostingSwitchesAreIndependent() {
        defer {
            LoggingControl.isEnabled = true
            SignpostingControl.isEnabled = true
        }

        SignpostingControl.isEnabled = false
        LoggingControl.isEnabled = true
        #expect(RuntimeControlledSignpostService._signpostLog === OSLog.disabled)
        #expect(RuntimeControlledService._osLog !== OSLog.disabled)

        SignpostingControl.isEnabled = true
        LoggingControl.isEnabled = false
        #expect(RuntimeControlledSignpostService._signpostLog !== OSLog.disabled)
        #expect(RuntimeControlledService._osLog === OSLog.disabled)
    }
}
