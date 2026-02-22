import Testing
@testable import SwiftStdlibToolbox

@Suite("Sequence Box Extensions")
struct SequenceExtensionTests {

    // MARK: - Sum

    @Test("sum() for integers")
    func sumIntegers() {
        #expect([1, 2, 3, 4, 5].box.sum() == 15)
    }

    @Test("sum() for doubles")
    func sumDoubles() {
        #expect([1.5, 2.5, 3.0].box.sum() == 7.0)
    }

    @Test("sum() for empty sequence")
    func sumEmpty() {
        #expect([Int]().box.sum() == 0)
    }

    // MARK: - Average

    @Test("average() for floating point")
    func averageFloat() {
        #expect([2.0, 4.0, 6.0].box.average() == 4.0)
    }

    @Test("average() for integers")
    func averageInteger() {
        #expect([2, 4, 6].box.average() == 4.0)
    }

    @Test("average() for empty collection")
    func averageEmpty() {
        let result: Double = [Double]().box.average()
        #expect(result == 0.0)
    }

    // MARK: - Contains

    @Test("contains(any:) with match")
    func containsAnyMatch() {
        #expect([1, 2, 3].box.contains(any: [3, 4, 5]))
    }

    @Test("contains(any:) without match")
    func containsAnyNoMatch() {
        #expect(![1, 2, 3].box.contains(any: [4, 5, 6]))
    }

    @Test("contains(all:) with all present")
    func containsAllPresent() {
        #expect([1, 2, 3, 4].box.contains(all: [1, 3]))
    }

    @Test("contains(all:) with some missing")
    func containsAllMissing() {
        #expect(![1, 2, 3].box.contains(all: [1, 5]))
    }

    // MARK: - Grouped

    @Test("grouped(by:)")
    func grouped() {
        let result = ["apple", "avocado", "banana", "blueberry"].box.grouped { $0.first! }
        #expect(result[Character("a")]?.count == 2)
        #expect(result[Character("b")]?.count == 2)
    }

    // MARK: - Keyed

    @Test("keyed(by:)")
    func keyed() {
        let result = ["apple", "banana", "cherry"].box.keyed { $0.first! }
        #expect(result[Character("a")] == "apple")
        #expect(result[Character("b")] == "banana")
        #expect(result[Character("c")] == "cherry")
    }

    @Test("keyed(by:) keeps last for duplicates")
    func keyedDuplicates() {
        let result = ["apple", "avocado"].box.keyed { $0.first! }
        #expect(result[Character("a")] == "avocado")
    }

    // MARK: - Min / Max by KeyPath

    struct Item {
        let name: String
        let value: Int
    }

    @Test("min(by:) keypath")
    func minByKeyPath() {
        let items = [Item(name: "a", value: 3), Item(name: "b", value: 1), Item(name: "c", value: 2)]
        let result = items.box.min(by: \.value)
        #expect(result?.name == "b")
    }

    @Test("max(by:) keypath")
    func maxByKeyPath() {
        let items = [Item(name: "a", value: 3), Item(name: "b", value: 1), Item(name: "c", value: 2)]
        let result = items.box.max(by: \.value)
        #expect(result?.name == "a")
    }

    @Test("min(by:) on empty sequence")
    func minByKeyPathEmpty() {
        let items = [Item]()
        #expect(items.box.min(by: \.value) == nil)
    }

    // MARK: - Type Filtering

    @Test("first(ofType:)")
    func firstOfType() {
        let mixed: [Any] = [1, "hello", 3.14, "world"]
        let result = mixed.box.first(ofType: String.self)
        #expect(result == "hello")
    }

    @Test("all(ofType:)")
    func allOfType() {
        let mixed: [Any] = [1, "hello", 3.14, "world"]
        let result = mixed.box.all(ofType: String.self)
        #expect(result == ["hello", "world"])
    }

    @Test("first(ofType:) returns nil when no match")
    func firstOfTypeNoMatch() {
        let ints: [Any] = [1, 2, 3]
        #expect(ints.box.first(ofType: String.self) == nil)
    }
}
