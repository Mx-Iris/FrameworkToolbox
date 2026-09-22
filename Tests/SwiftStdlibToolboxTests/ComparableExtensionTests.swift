import Testing
@testable import SwiftStdlibToolbox

/// `clamp` is reached through `.box`, so it only works if `box`'s setter writes
/// back. For as long as that setter was an empty `set {}`, every one of these
/// mutated a temporary the getter had just produced and threw the result away —
/// nothing failed to compile and no warning was emitted.
@Suite("Comparable box extensions")
struct ComparableExtensionTests {

    @Test("clamp(max:) writes back")
    func clampMaxWritesBack() {
        var value = 42
        value.box.clamp(max: 10)
        #expect(value == 10)
    }

    @Test("clamp(min:) writes back")
    func clampMinWritesBack() {
        var value = 3
        value.box.clamp(min: 10)
        #expect(value == 10)
    }

    @Test("clamp(to:) writes back")
    func clampToClosedRangeWritesBack() {
        var value = 99
        value.box.clamp(to: 0...10)
        #expect(value == 10)
    }

    @Test("clamp(to:) leaves an in-range value alone")
    func clampLeavesInRangeValueAlone() {
        var value = 5
        value.box.clamp(to: 0...10)
        #expect(value == 5)
    }

    @Test("clamped(to:) returns without mutating")
    func clampedReturnsWithoutMutating() {
        let value = 99
        #expect(value.box.clamped(to: 0...10) == 10)
        #expect(value == 99)
    }
}
