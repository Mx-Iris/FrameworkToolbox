import Combine
import Foundation
import FoundationToolbox
import Testing

// A storage macro without a type annotation. The property's type, the
// storage's generic argument and the projection's type are all left to the
// compiler, and the result has to behave exactly like the annotated spelling.

private let inferredDefaultsSuiteName = "com.frameworktoolbox.test.inferred-property-type"

private final class InferredDefaults {
    @UserDefault(key: "launchCount", suite: inferredDefaultsSuiteName)
    var launchCount = 0
}

@Suite(.serialized)
struct InferredStoragePropertyTests {
    @Test func inferredPropertyRoundTripsThroughUserDefaults() {
        defer { UserDefaults().removePersistentDomain(forName: inferredDefaultsSuiteName) }
        let defaults = InferredDefaults()

        // Spelled out to pin the inferred type: this line does not compile
        // unless the property is an `Int`.
        let initialValue: Int = defaults.launchCount
        #expect(initialValue == 0)

        defaults.launchCount = 3
        #expect(InferredDefaults().launchCount == 3)
    }

    @Test func inferredProjectionPublishesWrites() {
        defer { UserDefaults().removePersistentDomain(forName: inferredDefaultsSuiteName) }
        let defaults = InferredDefaults()
        var receivedValues: [Int] = []
        let subscription = defaults.$launchCount.sink { receivedValues.append($0) }
        defer { subscription.cancel() }

        defaults.launchCount = 7
        #expect(receivedValues.contains(7))
    }
}
