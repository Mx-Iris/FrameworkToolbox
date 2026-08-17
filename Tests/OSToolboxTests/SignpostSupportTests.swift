import Testing
import os

@testable import OSToolbox

// MARK: - System-defined signpost categories

@Suite
struct SignpostCategoryTests {

    /// These three strings are contracts with the system, not names we get to
    /// pick: `os/signpost.h` defines them as `OS_LOG_CATEGORY_POINTS_OF_INTEREST`,
    /// `OS_LOG_CATEGORY_DYNAMIC_TRACING` and
    /// `OS_LOG_CATEGORY_DYNAMIC_STACK_TRACING`. Getting a character wrong does
    /// not fail loudly — the category simply stops being special, and signposts
    /// quietly go missing from Instruments' default track. Hence a test.
    @Test func categoryNamesMatchTheSystemHeader() {
        #expect(LogCategory.pointsOfInterest.name == "PointsOfInterest")
        #expect(LogCategory.dynamicTracing.name == "DynamicTracing")
        #expect(LogCategory.dynamicStackTracing.name == "DynamicStackTracing")
    }

    /// The SDK exposes one of the three to Swift; pin ours against it rather
    /// than against a second copy of the same literal.
    @Test func pointsOfInterestMatchesTheSDKCategory() {
        #expect(LogCategory.pointsOfInterest.name == OSLog.Category.pointsOfInterest.rawValue)
    }
}

// MARK: - SignpostInterval

@Suite
struct SignpostIntervalTests {

    @Test func carriesNameAndIdentifier() {
        let log = OSLog(subsystem: "SignpostIntervalTests", category: "carries")
        let signpostID = OSSignpostID(log: log)
        let interval = SignpostInterval(
            name: "work",
            signpostID: signpostID,
            log: log,
            intervalState: nil
        )

        #expect("\(interval.name)" == "work")
        #expect(interval.signpostID == signpostID)
        // The handle is carried, not re-derived: `#signpost(.end, …)` closes the
        // interval on this very object, and the system pairs begin with end by
        // handle identity.
        #expect(interval.log === log)
    }

    /// A token begun through `OSSignposter` must hand the very same state object
    /// back, because `endInterval` uses its identity to detect a double-end.
    @Test
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func roundTripsTheIntervalStateItWasBegunWith() {
        let log = OSLog(subsystem: "SignpostIntervalTests", category: "roundTrip")
        let signposter = OSSignposter(logHandle: log)
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval("work", id: signpostID)
        let interval = SignpostInterval(
            name: "work",
            signpostID: signpostID,
            log: log,
            intervalState: intervalState
        )

        #expect(interval.osSignpostIntervalState === intervalState)
        signposter.endInterval(interval.name, interval.osSignpostIntervalState)
    }

    /// A token begun through the `os_signpost` path carries no state. Asking for
    /// one must still produce a usable value rather than trapping — that is the
    /// `beginState(id:)` recovery path.
    @Test
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func reconstructsIntervalStateWhenBegunWithoutOne() {
        let log = OSLog(subsystem: "SignpostIntervalTests", category: "reconstruct")
        let signpostID = OSSignpostID(log: log)
        let interval = SignpostInterval(
            name: "work",
            signpostID: signpostID,
            log: log,
            intervalState: nil
        )

        let reconstructed = interval.osSignpostIntervalState
        #expect(reconstructed._hasValue(id: signpostID, isOpen: true))
    }
}

// MARK: - Shared caches

@Suite
struct SignpostableMacroSupportTests {

    /// One subsystem/category pair must resolve to one `OSLog`, and to the same
    /// one whether it was reached through `@Signpostable` or `@Loggable` — the
    /// signpost helper deliberately forwards to the logging cache.
    @Test func signpostLogIsSharedPerSubsystemAndCategoryAndWithLoggable() {
        let first = SignpostableMacro._sharedSignpostLog(
            subsystem: "SignpostableMacroSupportTests",
            category: "shared"
        )
        let second = SignpostableMacro._sharedSignpostLog(
            subsystem: "SignpostableMacroSupportTests",
            category: "shared"
        )
        let throughLoggable = LoggableMacro._sharedOSLog(
            subsystem: "SignpostableMacroSupportTests",
            category: "shared"
        )

        #expect(first === second)
        #expect(first === throughLoggable)
    }

    @Test func signpostLogDiffersPerCategory() {
        let first = SignpostableMacro._sharedSignpostLog(
            subsystem: "SignpostableMacroSupportTests",
            category: "categoryOne"
        )
        let second = SignpostableMacro._sharedSignpostLog(
            subsystem: "SignpostableMacroSupportTests",
            category: "categoryTwo"
        )

        #expect(first !== second)
    }

    @Test func signpostLogIsSharedPerConformingType() {
        let first = SignpostableMacro._sharedSignpostLog(
            for: SignpostableMacroSupportTests.self,
            subsystem: "SignpostableMacroSupportTests",
            category: "perType"
        )
        let second = SignpostableMacro._sharedSignpostLog(
            for: SignpostableMacroSupportTests.self,
            subsystem: "SignpostableMacroSupportTests",
            category: "perType"
        )

        #expect(first === second)
    }

    /// `OSSignposter` is a struct, so identity cannot be asserted. What is
    /// observable is that the cache hands back a working signposter every time
    /// and agrees with itself on whether it is enabled.
    @Test
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func signposterCacheReturnsUsableSignposters() {
        let first = SignpostableMacro._sharedSignposter(
            subsystem: "SignpostableMacroSupportTests",
            category: "signposter"
        )
        let second = SignpostableMacro._sharedSignposter(
            subsystem: "SignpostableMacroSupportTests",
            category: "signposter"
        )
        #expect(first.isEnabled == second.isEnabled)

        let perType = SignpostableMacro._sharedSignposter(
            for: SignpostableMacroSupportTests.self,
            subsystem: "SignpostableMacroSupportTests",
            category: "signposterPerType"
        )
        let perTypeAgain = SignpostableMacro._sharedSignposter(
            for: SignpostableMacroSupportTests.self,
            subsystem: "SignpostableMacroSupportTests",
            category: "signposterPerType"
        )
        #expect(perType.isEnabled == perTypeAgain.isEnabled)

        // Exercise an actual interval through the cached signposter, so a broken
        // cache entry (e.g. a signposter built on the wrong log) shows up here.
        let signpostID = perType.makeSignpostID()
        let intervalState = perType.beginInterval("cached", id: signpostID)
        perType.endInterval("cached", intervalState)
    }
}
