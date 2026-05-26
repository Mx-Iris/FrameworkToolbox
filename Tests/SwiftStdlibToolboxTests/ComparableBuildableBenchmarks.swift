import Testing
import Dispatch
import Foundation
@testable import SwiftStdlibToolbox

// MARK: - Fixtures: Int-triple (pure value comparison, no String overhead)

private struct BenchTripleManual: Comparable {
    let a: Int
    let b: Int
    let c: Int

    static func < (lhs: BenchTripleManual, rhs: BenchTripleManual) -> Bool {
        if lhs.a != rhs.a { return lhs.a < rhs.a }
        if lhs.b != rhs.b { return lhs.b < rhs.b }
        return lhs.c < rhs.c
    }

    static func == (lhs: BenchTripleManual, rhs: BenchTripleManual) -> Bool {
        lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c
    }
}

/// Stored-let form: terser to write but blocks `KeyPath` literal
/// propagation, so each comparison goes through the generic `KeyPath`
/// subscript.
private struct BenchTripleBuildable: ComparableBuildable {
    let a: Int
    let b: Int
    let c: Int

    static let comparableDefinition = makeComparable {
        compare(\.a)
        compare(\.b)
        compare(\.c)
    }
}

/// Recommended form: a computed property lets the optimizer inline the
/// whole step tree into the `<` / `==` call site, with literal
/// `KeyPath`s in view — final SIL is equivalent to a hand-written
/// comparator.
private struct BenchTripleBuildableVar: ComparableBuildable {
    let a: Int
    let b: Int
    let c: Int

    static var comparableDefinition: some ComparisonStepProtocol<BenchTripleBuildableVar> {
        makeComparable {
            compare(\.a)
            compare(\.b)
            compare(\.c)
        }
    }
}

// MARK: - Fixtures: mixed Int / String / Double

private struct BenchPersonManual: Comparable {
    let age: Int
    let name: String
    let score: Double

    static func < (lhs: BenchPersonManual, rhs: BenchPersonManual) -> Bool {
        if lhs.age != rhs.age { return lhs.age < rhs.age }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.score < rhs.score
    }

    static func == (lhs: BenchPersonManual, rhs: BenchPersonManual) -> Bool {
        lhs.age == rhs.age && lhs.name == rhs.name && lhs.score == rhs.score
    }
}

/// Stored-let form: see `BenchTripleBuildable` for the cost.
private struct BenchPersonBuildable: ComparableBuildable {
    let age: Int
    let name: String
    let score: Double

    static let comparableDefinition = makeComparable {
        compare(\.age)
        compare(\.name)
        compare(\.score)
    }
}

/// Recommended form: see `BenchTripleBuildableVar`.
private struct BenchPersonBuildableVar: ComparableBuildable {
    let age: Int
    let name: String
    let score: Double

    static var comparableDefinition: some ComparisonStepProtocol<BenchPersonBuildableVar> {
        makeComparable {
            compare(\.age)
            compare(\.name)
            compare(\.score)
        }
    }
}

// MARK: - Helpers

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private func makeTriples(count: Int, seed: UInt64 = 0xC0FFEE) -> [(Int, Int, Int)] {
    var rng = SeededRNG(state: seed)
    var result: [(Int, Int, Int)] = []
    result.reserveCapacity(count)
    for _ in 0..<count {
        let firstField = Int.random(in: 0...100, using: &rng)
        let secondField = Int.random(in: 0...100, using: &rng)
        let thirdField = Int.random(in: 0...100, using: &rng)
        result.append((firstField, secondField, thirdField))
    }
    return result
}

private func makePersons(count: Int, seed: UInt64 = 0xC0FFEE) -> [(Int, String, Double)] {
    var rng = SeededRNG(state: seed)
    var result: [(Int, String, Double)] = []
    result.reserveCapacity(count)
    for _ in 0..<count {
        let age = Int.random(in: 0...100, using: &rng)
        let nameIndex = Int.random(in: 0...500, using: &rng)
        let score = Double.random(in: 0..<1000, using: &rng)
        result.append((age, "name_\(nameIndex)", score))
    }
    return result
}

private func elapsedNanoseconds(_ body: () -> Void) -> UInt64 {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return DispatchTime.now().uptimeNanoseconds - start
}

private func bestOf(_ runs: Int, _ body: () -> Void) -> UInt64 {
    var best = UInt64.max
    for _ in 0..<runs {
        let elapsed = elapsedNanoseconds(body)
        if elapsed < best { best = elapsed }
    }
    return best
}

private func formatNanoseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%9.3f ms", Double(nanoseconds) / 1_000_000)
}

private func ratio(_ value: UInt64, over baseline: UInt64) -> String {
    guard baseline > 0 else { return " n/a " }
    return String(format: "%5.2fx", Double(value) / Double(baseline))
}

private func printRow(_ label: String, time: UInt64, baseline: UInt64) {
    print("  \(label.padding(toLength: 20, withPad: " ", startingAt: 0)) \(formatNanoseconds(time))   [\(ratio(time, over: baseline)) vs manual]")
}

private let benchmarkHeaderOnce: Void = {
    #if DEBUG
    print("")
    print("⚠️  ComparableBuildable benchmarks are running in DEBUG mode.")
    print("    For meaningful numbers, rerun with:")
    print("    swift test -c release --filter ComparableBuildableBenchmarks 2>&1 | xcsift")
    print("")
    #endif
}()

// MARK: - Benchmarks

@Suite("ComparableBuildable benchmarks", .serialized)
struct ComparableBuildableBenchmarks {

    init() {
        _ = benchmarkHeaderOnce
    }

    // MARK: Correctness sanity checks

    @Test("sort produces identical ordering across implementations (triples)")
    func sortOrderingMatches() {
        let raw = makeTriples(count: 200)
        let manualSorted = raw.map { BenchTripleManual(a: $0.0, b: $0.1, c: $0.2) }.sorted()
        let buildableSorted = raw.map { BenchTripleBuildable(a: $0.0, b: $0.1, c: $0.2) }.sorted()
        let buildableVarSorted = raw.map { BenchTripleBuildableVar(a: $0.0, b: $0.1, c: $0.2) }.sorted()

        for index in manualSorted.indices {
            #expect(manualSorted[index].a == buildableSorted[index].a)
            #expect(manualSorted[index].b == buildableSorted[index].b)
            #expect(manualSorted[index].c == buildableSorted[index].c)
            #expect(manualSorted[index].a == buildableVarSorted[index].a)
            #expect(manualSorted[index].b == buildableVarSorted[index].b)
            #expect(manualSorted[index].c == buildableVarSorted[index].c)
        }
    }

    // MARK: Sort benchmarks

    @Test("sort 10k Int-triples")
    func sortTriples10k() {
        let raw = makeTriples(count: 10_000)
        let manual = raw.map { BenchTripleManual(a: $0.0, b: $0.1, c: $0.2) }
        let buildable = raw.map { BenchTripleBuildable(a: $0.0, b: $0.1, c: $0.2) }
        let buildableVar = raw.map { BenchTripleBuildableVar(a: $0.0, b: $0.1, c: $0.2) }

        _ = manual.sorted()
        _ = buildable.sorted()
        _ = buildableVar.sorted()

        let runs = 5
        let manualTime = bestOf(runs) { var copy = manual; copy.sort(); blackhole(copy) }
        let buildableLetTime = bestOf(runs) { var copy = buildable; copy.sort(); blackhole(copy) }
        let buildableVarTime = bestOf(runs) { var copy = buildableVar; copy.sort(); blackhole(copy) }

        print("")
        print("=== sort 10k Int-triples (best of \(runs) runs) ===")
        printRow("manual",          time: manualTime,       baseline: manualTime)
        printRow("buildable (let)", time: buildableLetTime, baseline: manualTime)
        printRow("buildable (var)", time: buildableVarTime, baseline: manualTime)
    }

    @Test("sort 100k Int-triples")
    func sortTriples100k() {
        let raw = makeTriples(count: 100_000)
        let manual = raw.map { BenchTripleManual(a: $0.0, b: $0.1, c: $0.2) }
        let buildable = raw.map { BenchTripleBuildable(a: $0.0, b: $0.1, c: $0.2) }
        let buildableVar = raw.map { BenchTripleBuildableVar(a: $0.0, b: $0.1, c: $0.2) }

        _ = manual.sorted()
        _ = buildable.sorted()
        _ = buildableVar.sorted()

        let runs = 3
        let manualTime = bestOf(runs) { var copy = manual; copy.sort(); blackhole(copy) }
        let buildableLetTime = bestOf(runs) { var copy = buildable; copy.sort(); blackhole(copy) }
        let buildableVarTime = bestOf(runs) { var copy = buildableVar; copy.sort(); blackhole(copy) }

        print("")
        print("=== sort 100k Int-triples (best of \(runs) runs) ===")
        printRow("manual",          time: manualTime,       baseline: manualTime)
        printRow("buildable (let)", time: buildableLetTime, baseline: manualTime)
        printRow("buildable (var)", time: buildableVarTime, baseline: manualTime)
    }

    @Test("sort 10k Persons (Int + String + Double)")
    func sortPersons10k() {
        let raw = makePersons(count: 10_000)
        let manual = raw.map { BenchPersonManual(age: $0.0, name: $0.1, score: $0.2) }
        let buildable = raw.map { BenchPersonBuildable(age: $0.0, name: $0.1, score: $0.2) }
        let buildableVar = raw.map { BenchPersonBuildableVar(age: $0.0, name: $0.1, score: $0.2) }

        _ = manual.sorted()
        _ = buildable.sorted()
        _ = buildableVar.sorted()

        let runs = 5
        let manualTime = bestOf(runs) { var copy = manual; copy.sort(); blackhole(copy) }
        let buildableLetTime = bestOf(runs) { var copy = buildable; copy.sort(); blackhole(copy) }
        let buildableVarTime = bestOf(runs) { var copy = buildableVar; copy.sort(); blackhole(copy) }

        print("")
        print("=== sort 10k Persons (best of \(runs) runs) ===")
        printRow("manual",          time: manualTime,       baseline: manualTime)
        printRow("buildable (let)", time: buildableLetTime, baseline: manualTime)
        printRow("buildable (var)", time: buildableVarTime, baseline: manualTime)
    }

    // MARK: Raw comparison microbenchmark

    @Test("1M raw < comparisons (Int-triples)")
    func rawComparisons() {
        let raw = makeTriples(count: 1024)
        let manual = raw.map { BenchTripleManual(a: $0.0, b: $0.1, c: $0.2) }
        let buildable = raw.map { BenchTripleBuildable(a: $0.0, b: $0.1, c: $0.2) }
        let buildableVar = raw.map { BenchTripleBuildableVar(a: $0.0, b: $0.1, c: $0.2) }

        let iterations = 1_000_000

        // warm up
        _ = runManualComparisons(manual, iterations: 1000)
        _ = runBuildableComparisons(buildable, iterations: 1000)
        _ = runBuildableVarComparisons(buildableVar, iterations: 1000)

        let runs = 5
        let manualTime = bestOf(runs) {
            blackhole(runManualComparisons(manual, iterations: iterations))
        }
        let buildableLetTime = bestOf(runs) {
            blackhole(runBuildableComparisons(buildable, iterations: iterations))
        }
        let buildableVarTime = bestOf(runs) {
            blackhole(runBuildableVarComparisons(buildableVar, iterations: iterations))
        }

        print("")
        print("=== \(iterations) raw '<' comparisons (best of \(runs) runs) ===")
        printRow("manual",          time: manualTime,       baseline: manualTime)
        printRow("buildable (let)", time: buildableLetTime, baseline: manualTime)
        printRow("buildable (var)", time: buildableVarTime, baseline: manualTime)
    }
}

// MARK: - @inline(never) workhorses to defeat constant folding

@inline(never)
private func runManualComparisons(_ items: [BenchTripleManual], iterations: Int) -> Int {
    var accumulator = 0
    let mask = items.count - 1
    for index in 0..<iterations {
        let left = items[index & mask]
        let right = items[(index &+ 1) & mask]
        if left < right { accumulator &+= 1 }
    }
    return accumulator
}

@inline(never)
private func runBuildableComparisons(_ items: [BenchTripleBuildable], iterations: Int) -> Int {
    var accumulator = 0
    let mask = items.count - 1
    for index in 0..<iterations {
        let left = items[index & mask]
        let right = items[(index &+ 1) & mask]
        if left < right { accumulator &+= 1 }
    }
    return accumulator
}

@inline(never)
private func runBuildableVarComparisons(_ items: [BenchTripleBuildableVar], iterations: Int) -> Int {
    var accumulator = 0
    let mask = items.count - 1
    for index in 0..<iterations {
        let left = items[index & mask]
        let right = items[(index &+ 1) & mask]
        if left < right { accumulator &+= 1 }
    }
    return accumulator
}

@inline(never)
private func blackhole<T>(_ value: T) {
    // Prevent dead-code elimination of benchmark workloads.
    withExtendedLifetime(value) {}
}
