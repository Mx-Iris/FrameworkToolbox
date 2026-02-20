import Testing
@testable import SwiftStdlibToolbox

@Suite("Collection Box Extensions")
struct CollectionExtensionTests {

    // MARK: - Safe Subscript (existing)

    @Test("safe subscript returns element")
    func safeSubscriptValid() {
        #expect([10, 20, 30].box[safe: 1] == 20)
    }

    @Test("safe subscript returns nil for out of bounds")
    func safeSubscriptOutOfBounds() {
        #expect([10, 20, 30].box[safe: 5] == nil)
    }

    @Test("safe subscript returns nil for negative index")
    func safeSubscriptNegative() {
        #expect([10, 20, 30].box[safe: -1] == nil)
    }

    // MARK: - First / Last N

    @Test("first(n) returns first n elements")
    func firstN() {
        let result = Array([1, 2, 3, 4, 5].box.first(3))
        #expect(result == [1, 2, 3])
    }

    @Test("first(n) with n greater than count")
    func firstNExceedsCount() {
        let result = Array([1, 2].box.first(10))
        #expect(result == [1, 2])
    }

    @Test("first(0) returns empty")
    func firstZero() {
        let result = Array([1, 2, 3].box.first(0))
        #expect(result.isEmpty)
    }

    @Test("last(n) returns last n elements")
    func lastN() {
        let result = Array([1, 2, 3, 4, 5].box.last(3))
        #expect(result == [3, 4, 5])
    }

    @Test("last(n) with n greater than count")
    func lastNExceedsCount() {
        let result = Array([1, 2].box.last(10))
        #expect(result == [1, 2])
    }

    @Test("last(0) returns empty")
    func lastZero() {
        let result = Array([1, 2, 3].box.last(0))
        #expect(result.isEmpty)
    }

    // MARK: - Chunked by Size

    @Test("chunked(size:) even split")
    func chunkedSizeEven() {
        let result = [1, 2, 3, 4, 5, 6].box.chunked(size: 2)
        #expect(result == [[1, 2], [3, 4], [5, 6]])
    }

    @Test("chunked(size:) with remainder")
    func chunkedSizeRemainder() {
        let result = [1, 2, 3, 4, 5].box.chunked(size: 2)
        #expect(result == [[1, 2], [3, 4], [5]])
    }

    @Test("chunked(size: 1)")
    func chunkedSizeOne() {
        let result = [1, 2, 3].box.chunked(size: 1)
        #expect(result == [[1], [2], [3]])
    }

    @Test("chunked(size:) on empty array")
    func chunkedSizeEmpty() {
        let result = [Int]().box.chunked(size: 3)
        #expect(result.isEmpty)
    }

    // MARK: - Chunked by Amount

    @Test("chunked(amount:) even split")
    func chunkedAmountEven() {
        let result = [1, 2, 3, 4, 5, 6].box.chunked(amount: 3)
        #expect(result == [[1, 2], [3, 4], [5, 6]])
    }

    @Test("chunked(amount:) uneven split")
    func chunkedAmountUneven() {
        let result = [1, 2, 3, 4, 5].box.chunked(amount: 2)
        #expect(result == [[1, 2, 3], [4, 5]])
    }

    @Test("chunked(amount: 1)")
    func chunkedAmountOne() {
        let result = [1, 2, 3].box.chunked(amount: 1)
        #expect(result == [[1, 2, 3]])
    }
}
