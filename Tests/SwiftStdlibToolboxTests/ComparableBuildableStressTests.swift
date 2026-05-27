import Testing
@testable import SwiftStdlibToolbox

// MARK: - Fixture: 20 fields (stress CompositeComparisonStep nesting)

private struct Twenty20Buildable: ComparableBuildable {
    let f00: Int, f01: Int, f02: Int, f03: Int, f04: Int
    let f05: Int, f06: Int, f07: Int, f08: Int, f09: Int
    let f10: Int, f11: Int, f12: Int, f13: Int, f14: Int
    let f15: Int, f16: Int, f17: Int, f18: Int, f19: Int

    static var comparableDefinition: some ComparisonStep<Twenty20Buildable> {
        compare(\.f00); compare(\.f01); compare(\.f02); compare(\.f03); compare(\.f04)
        compare(\.f05); compare(\.f06); compare(\.f07); compare(\.f08); compare(\.f09)
        compare(\.f10); compare(\.f11); compare(\.f12); compare(\.f13); compare(\.f14)
        compare(\.f15); compare(\.f16); compare(\.f17); compare(\.f18); compare(\.f19)
    }

    static func make(seed: Int) -> Twenty20Buildable {
        func field(_ salt: Int) -> Int {
            let mixed = (seed &* 2654435761) ^ (salt &* 1442695040)
            return abs(mixed) % 5
        }
        return Twenty20Buildable(
            f00: field(0), f01: field(1), f02: field(2), f03: field(3), f04: field(4),
            f05: field(5), f06: field(6), f07: field(7), f08: field(8), f09: field(9),
            f10: field(10), f11: field(11), f12: field(12), f13: field(13), f14: field(14),
            f15: field(15), f16: field(16), f17: field(17), f18: field(18), f19: field(19)
        )
    }
}

// MARK: - Fixture: every builder DSL feature

private struct AllBuilderFeatures: ComparableBuildable {
    let a: Int
    let b: Int
    let c: Int
    let d: Int
    let e: Int

    static let useDescendingB = false
    static let includeC = true
    static let extraKeyPaths: [KeyPath<AllBuilderFeatures, Int>] = [\.d]

    static var comparableDefinition: some ComparisonStep<AllBuilderFeatures> {
        // basic
        compare(\.a)
        // buildEither (if/else)
        if Self.useDescendingB {
            compareDescending(\.b)
        } else {
            compare(\.b)
        }
        // buildOptional (if without else)
        if Self.includeC {
            compare(\.c)
        }
        // buildArray (for loop)
        for keyPath in Self.extraKeyPaths {
            compare(keyPath)
        }
        // tail
        compare(\.e)
    }

    static func make(seed: Int) -> AllBuilderFeatures {
        func field(_ salt: Int) -> Int {
            let mixed = (seed &* 2654435761) ^ (salt &* 1442695040)
            return abs(mixed) % 4
        }
        return AllBuilderFeatures(a: field(0), b: field(1), c: field(2), d: field(3), e: field(4))
    }
}

// MARK: - Fixture: every leaf step type

private struct AllStepTypes: ComparableBuildable {
    let id: Int
    let optionalText: String?
    let score: Double
    let flag: Bool

    static var comparableDefinition: some ComparisonStep<AllStepTypes> {
        compare(\.id)
        compare(\.optionalText)
        compareDescending(\.score)
        compareCustom(\.flag) { lhs, rhs in
            switch (lhs, rhs) {
            case (false, true): return .ascending
            case (true, false): return .descending
            default: return .equal
            }
        }
    }
}

// MARK: - Stress suite

@Suite("ComparableBuildable stress tests")
struct ComparableBuildableStressTests {

    // MARK: Compile / sort smoke

    @Test("20-field deep nesting: compile + sort 1k items")
    func deepNestingSmall() {
        let items = (0..<1000).map { Twenty20Buildable.make(seed: $0) }
        let sorted = items.sorted()
        #expect(sorted.count == items.count)
        for index in 1..<sorted.count {
            #expect(!(sorted[index] < sorted[index - 1]))
        }
    }

    @Test("20-field deep nesting: sort 50k items without crashing")
    func deepNestingLarge() {
        let items = (0..<50_000).map { Twenty20Buildable.make(seed: $0) }
        let sorted = items.sorted()
        #expect(sorted.count == items.count)
        for index in 1..<sorted.count {
            #expect(!(sorted[index] < sorted[index - 1]))
        }
    }

    @Test("all builder DSL features in one definition")
    func allBuilderFeatures() {
        let items = (0..<500).map { AllBuilderFeatures.make(seed: $0) }
        let sorted = items.sorted()
        #expect(sorted.count == items.count)
        for index in 1..<sorted.count {
            #expect(!(sorted[index] < sorted[index - 1]))
        }
    }

    @Test("all step types mixed: keyPath / optional / descending / custom")
    func allStepTypesMixed() {
        let items = (0..<500).map { i -> AllStepTypes in
            AllStepTypes(
                id: i % 10,
                optionalText: i % 5 == 0 ? nil : "t_\(i % 7)",
                score: Double((i &* 17) % 100),
                flag: i % 2 == 0
            )
        }
        let sorted = items.sorted()
        for index in 1..<sorted.count {
            #expect(!(sorted[index] < sorted[index - 1]))
        }

        // Determinism: sorting twice is identical.
        let sorted2 = items.sorted()
        for index in items.indices {
            #expect(sorted[index].id == sorted2[index].id)
            #expect(sorted[index].optionalText == sorted2[index].optionalText)
            #expect(sorted[index].score == sorted2[index].score)
            #expect(sorted[index].flag == sorted2[index].flag)
        }
    }

    // MARK: Comparable algebra

    @Test("equality is reflexive and symmetric")
    func equalityAxioms() {
        let lhs = Twenty20Buildable.make(seed: 0xCAFE)
        let lhsCopy = Twenty20Buildable.make(seed: 0xCAFE)
        let rhs = Twenty20Buildable.make(seed: 0xBEEF)

        #expect(lhs == lhs)
        #expect(lhs == lhsCopy)
        #expect(lhsCopy == lhs)
        #expect((lhs == rhs) == (rhs == lhs))
    }

    @Test("less-than is antisymmetric and irreflexive")
    func lessThanAxioms() {
        let items = (0..<60).map { Twenty20Buildable.make(seed: $0) }
        for value in items {
            #expect(!(value < value), "Irreflexivity violated")
        }
        for left in items {
            for right in items where left != right {
                if left < right {
                    #expect(!(right < left), "Antisymmetry violated")
                }
            }
        }
    }

    @Test("less-than is transitive over 25 items (15625 triples)")
    func lessThanTransitivity() {
        let items = (0..<25).map { Twenty20Buildable.make(seed: $0) }
        for a in items {
            for b in items {
                guard a < b else { continue }
                for c in items where b < c {
                    #expect(a < c, "Transitivity violated")
                }
            }
        }
    }

    // MARK: Edge cases

    @Test("optional KeyPath: nil sorts before non-nil consistently")
    func optionalKeyPathOrdering() {
        let withNil = AllStepTypes(id: 1, optionalText: nil, score: 0, flag: false)
        let withValue = AllStepTypes(id: 1, optionalText: "z", score: 0, flag: false)

        #expect(withNil < withValue)
        #expect(!(withValue < withNil))
        #expect(withNil != withValue)
    }

    @Test("repeated sort of pre-sorted array is idempotent")
    func idempotentSort() {
        let items = (0..<2000).map { Twenty20Buildable.make(seed: $0) }
        let firstPass = items.sorted()
        let secondPass = firstPass.sorted()
        for index in firstPass.indices {
            #expect(firstPass[index] == secondPass[index])
        }
    }
}
