import Foundation
import FrameworkToolbox
import SwiftStdlibToolbox

extension NSRange: RangeRepresentable {
    public init(uncheckedBounds bounds: (lower: Int, upper: Int)) {
        self.init(location: bounds.lower, length: bounds.upper - bounds.lower)
    }
}

extension CFRange: RangeRepresentable {
    public init(uncheckedBounds bounds: (lower: CFIndex, upper: CFIndex)) {
        self.init(location: bounds.lower, length: bounds.upper - bounds.lower)
    }
}

extension NSRange: Swift.RandomAccessCollection, Swift.RangeExpression, Swift.BidirectionalCollection, Swift.Sequence, Swift.Collection {
    public var startIndex: Int { 0 }

    public var endIndex: Int { box.isNotFound ? 0 : length }

    public subscript(index: Int) -> Int {
        precondition(indices.contains(index), "Index out of range")
        return location + index
    }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public func relative<C>(to collection: C) -> Range<Int> where C: Collection, Int == C.Index {
        guard location != NSNotFound else { return 0 ..< 0 }
        let lowerBound = Swift.max(collection.startIndex, location)
        let upperBound = Swift.min(collection.endIndex, location + length)
        return lowerBound ..< Swift.max(lowerBound, upperBound)
    }
}

extension CFRange: Swift.Collection, Swift.BidirectionalCollection, Swift.RandomAccessCollection, Swift.RangeExpression, Swift.Sequence {
    public var startIndex: CFIndex { lowerBound }

    public var endIndex: CFIndex { upperBound }

    public func index(after i: CFIndex) -> CFIndex {
        precondition(i < endIndex, "Index out of bounds")
        return i + 1
    }

    public func index(before i: CFIndex) -> CFIndex {
        precondition(i > startIndex, "Index out of bounds")
        return i - 1
    }

    public subscript(position: CFIndex) -> CFIndex {
        precondition(contains(position), "Index out of bounds")
        return position
    }

    public var count: Int { length }
    
    public func relative<C>(to collection: C) -> Range<CFIndex> where C: Collection, CFIndex == C.Index {
        location..<Swift.min(location + length, collection.count)
    }
    
    public func contains(_ bound: CFIndex) -> Bool {
        lowerBound <= bound && bound < upperBound
    }
    
    public var lowerBound: CFIndex { location }
    
    public var upperBound: CFIndex { location + length }
}

extension FrameworkToolbox<NSRange> {
    /// `ClosedRange` representation of the range.
    public var closedRange: ClosedRange<Int> {
        base.length > 0 ? base.location ... (base.location + base.length - 1) : base.location ... base.location
    }

    /// `Range` representation of the range.
    public var range: Range<Int> {
        base.location ..< (base.location + base.length)
    }

    /// `CFRange` representation of the range.
    public var cfRange: CFRange {
        CFRange(location: base.location, length: base.length)
    }

    /// The maximum value.
    public var max: Int {
        NSMaxRange(base)
    }

    /// A Boolean value indicating whether the range is not found.
    public var isNotFound: Bool {
        base.location == NSNotFound
    }

    /// A Boolean value indicating whether the given range is contained within the range.
    public func contains(_ range: NSRange) -> Bool {
        guard !isNotFound, !range.box.isNotFound else { return false }
        return range.lowerBound >= base.lowerBound && range.upperBound <= base.upperBound
    }

    /// Return a copied NSRange but whose location is shifted toward the given `offset`.
    ///
    /// - Parameter offset: The offset to shift.
    /// - Returns: A new NSRange.
    public func shifted(by offset: Int) -> NSRange {
        NSRange(location: base.location + offset, length: base.length)
    }

    /// A Boolean value indicating whether this range and the given range contain an element in common.
    public func overlaps(_ other: NSRange) -> Bool {
        base.intersection(other) != nil
    }

    /// The zero range.
    public static let zero = NSRange(location: 0, length: 0)

    /// Not found range.
    public static let notFound = NSRange(location: NSNotFound, length: 0)
}

extension FrameworkToolbox where Base: Sequence, Base.Element == NSRange {
    /// The range that contains all ranges.
    public var union: NSRange? {
        guard let min = min, let max = max else { return nil }
        return NSRange(min ..< max)
    }

    /// Returns the minimum lower bound in the sequence.
    public var min: Int? {
        base.filter { !$0.box.isNotFound }.map(\.lowerBound).min()
    }

    /// Returns the maximum upper bound in the sequence.
    public var max: Int? {
        base.filter { !$0.box.isNotFound }.map(\.upperBound).max()
    }
}

extension FrameworkToolbox<CFRange> {
    /// The range as `NSRange`.
    public var nsRange: NSRange { .init(location: base.location, length: base.length) }
}
