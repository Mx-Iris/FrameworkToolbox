import OSToolbox

// Compile-time guard for `@Signpostable` / `#signpost`, mirroring the `@Loggable`
// one next door: no file in this target imports Foundation, so any expansion
// that needs it fails the build here.
//
// It doubles as the coverage matrix for the three call forms, since a macro
// expansion is only known to compile once something actually expands it.

enum SignpostGuardError: Error {
    case failed
}

@Signpostable
struct SignpostGuardService {

    // MARK: .event

    func emitEvent() {
        #signpost(.event, "plain event")
    }

    func emitEventWithMessage(index: Int) {
        #signpost(.event, "event with message", "index=\(index, privacy: .public)")
    }

    func emitEventUnderACategory() {
        #signpost(.event, category: .pointsOfInterest, "event on the points-of-interest track")
    }

    func emitEventWithEverything(name: String, index: Int) {
        #signpost(
            .event,
            category: .dynamicTracing,
            "event with category and message",
            "name=\(name, privacy: .public) index=\(index, privacy: .private)",
            id: Self.makeSignpostID()
        )
    }

    // MARK: .begin / .end across calls

    func beginAndEndSeparately(byteCount: Int) {
        let interval = #signpost(.begin, "separate", "bytes=\(byteCount)")
        #signpost(.end, interval, "ok=\(true, privacy: .public)")
    }

    func beginAndEndWithoutMessages() {
        let interval = #signpost(.begin, "separate, no message")
        #signpost(.end, interval)
    }

    func beginAndEndUnderACategory() {
        let interval = #signpost(.begin, category: .pointsOfInterest, "separate, categorised")
        #signpost(.end, interval)
    }

    func beginWithAnIdentifierDerivedFromAnObject(object: AnyObject) {
        let interval = #signpost(.begin, "derived id", id: Self.makeSignpostID(from: object))
        #signpost(.end, interval)
    }

    // MARK: #signpostInterval — every body shape

    func scopedReturningValue() -> Int {
        #signpostInterval("scoped, returning") {
            41 + 1
        }
    }

    func scopedReturningVoid() {
        #signpostInterval("scoped, void") {
            _ = 1 + 1
        }
    }

    func scopedMultipleStatements() -> Int {
        #signpostInterval("scoped, multi-statement") {
            let first = 20
            let second = 22
            return first + second
        }
    }

    func scopedThrowing(shouldFail: Bool) throws -> Int {
        try #signpostInterval("scoped, throwing") {
            if shouldFail { throw SignpostGuardError.failed }
            return 42
        }
    }

    func scopedAsync() async -> Int {
        await #signpostInterval("scoped, async") {
            await produceAsynchronously()
        }
    }

    func scopedAsyncThrowing() async throws -> Int {
        try await #signpostInterval("scoped, async throwing") {
            try await produceAsynchronouslyOrFail()
        }
    }

    func scopedUnderACategory() -> Int {
        #signpostInterval("scoped, categorised", category: .pointsOfInterest) {
            42
        }
    }

    func scopedWithAnExplicitIdentifier() -> Int {
        #signpostInterval("scoped, explicit id", id: Self.makeSignpostID()) {
            42
        }
    }

    private func produceAsynchronously() async -> Int { 42 }
    private func produceAsynchronouslyOrFail() async throws -> Int { 42 }
}

// An interval may be closed from a type that is not itself `@Signpostable` —
// the token carries the log handle, name and identifier it began with.
struct IntervalConsumerWithoutSignpostable {
    func end(_ interval: SignpostInterval) {
        #signpost(.end, interval)
    }
}
