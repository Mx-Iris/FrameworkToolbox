import FrameworkToolbox

/// A type that represents a range.
public protocol RangeRepresentable: RangeExpression {
    /// The range’s lower bound.
    var lowerBound: Bound { get }
    /// The range’s upper bound.
    var upperBound: Bound { get }
    /// Creates an instance with the given bounds.
    init(uncheckedBounds bounds: (lower: Bound, upper: Bound))
}

extension ClosedRange: RangeRepresentable {}

extension Range: RangeRepresentable {}

extension FrameworkToolbox where Base: RangeRepresentable, Base.Bound: FrameworkToolboxCompatible {
    /// Clamps the range to the lower- and upper bound of the specified range.
    ///
    /// - Parameter range: The range fo clamp to.
    public func clamped<Range: RangeRepresentable>(to range: Range) -> Base where Range.Bound == Base.Bound {
        .init(uncheckedBounds: (base.lowerBound.box.clamped(min: range.lowerBound), base.upperBound.box.clamped(max: range.upperBound)))
    }

    /// Clamps the range to the lower- and upper bound of the specified range.
    ///
    /// - Parameter range: The range fo clamp to.
    public mutating func clamp<Range: RangeRepresentable>(to range: Range) where Range.Bound == Base.Bound {
        base = clamped(to: range)
    }

    /// Clamps the lower bound to the minimum value.
    ///
    /// - Parameter minValue: The minimum value to clamp the lower bound.
    public mutating func clamp(min minValue: Base.Bound) {
        base = clamped(min: minValue)
    }

    /// Clamps the lower bound to the minimum value.
    ///
    /// - Parameter minValue: The minimum value to clamp the lower bound.
    public func clamped(min minValue: Base.Bound) -> Base {
        .init(uncheckedBounds: base.upperBound < minValue ? (minValue, minValue) : (base.lowerBound.box.clamped(min: minValue), base.upperBound.box.clamped(min: minValue)))
    }

    /// Clamps the upper bound to the maximum value.
    ///
    /// - Parameter maxValue: The maximum value to clamp the upper bound.
    public mutating func clamp(max maxValue: Base.Bound) {
        base = clamped(max: maxValue)
    }

    /// Clamps the upper bound to the maximum value.
    ///
    /// - Parameter maxValue: The maximum value to clamp the upper bound.
    public func clamped(max maxValue: Base.Bound) -> Base {
        .init(uncheckedBounds: base.lowerBound > maxValue ? (maxValue, maxValue) : (base.lowerBound, base.upperBound.box.clamped(max: maxValue)))
    }

    /// A Boolean value indicating whether the other range is fully contained within the range.
    public func contains<R: RangeRepresentable>(_ range: R) -> Bool where R.Bound == Base.Bound {
        range.lowerBound >= base.lowerBound && range.upperBound <= base.upperBound
    }

    /// A Boolean value indicating whether the other range overlaps the range.
    ///
    /// It returns `true` if the other range's lower bound is smaller than the current's lower bound and the other range's upper bound is larger than the current's upper bound.
    ///
    /// Example usage:
    ///
    /// ```swift
    /// let range = 3...7
    /// range.overlaps(5...10) // true
    /// range.overlaps(8...12) // false
    /// ```
    public func overlaps<R: RangeRepresentable>(_ other: R) -> Bool where R.Bound == Base.Bound {
        base.lowerBound < other.upperBound && base.upperBound > other.lowerBound
    }

    /// Returns the intersection of this range with another range, or `nil` if they do not overlap.
    ///
    /// Example usage:
    ///
    /// ```swift
    /// let range = 3...7
    /// range.intersection(5...10) // 5...7
    /// ```
    public func intersection<R: RangeRepresentable>(_ other: R) -> Base? where R.Bound == Base.Bound {
        let lower = Swift.max(base.lowerBound, other.lowerBound)
        let upper = Swift.min(base.upperBound, other.upperBound)
        return lower <= upper ? .init(uncheckedBounds: (lower, upper)) : nil
    }

    /// Returns the smallest range that fully contains both ranges.
    ///
    /// Example usage:
    ///
    /// ```swift
    /// let range = 3...7
    /// range.union(5...10) // 3...10
    /// ```
    public func union<R: RangeRepresentable>(_ other: R) -> Base where R.Bound == Base.Bound {
        .init(uncheckedBounds: (Swift.min(base.lowerBound, other.lowerBound), Swift.max(base.upperBound, other.upperBound)))
    }
}

extension RangeRepresentable {
    /// Creates an range from the specified values.
    public init(checkedBounds value1: Bound, _ value2: Bound) {
        self = Self(uncheckedBounds: (Swift.min(value1, value2), Swift.max(value1, value2)))
    }
}

extension FrameworkToolbox where Base: RangeRepresentable, Base.Bound: Strideable, Base.Bound: FrameworkToolboxCompatible {
    /// The distance between the lower bound and upper bound.
    public var length: Base.Bound.Stride {
        base.lowerBound.distance(to: base.upperBound)
    }
}

extension FrameworkToolbox where Base: RangeRepresentable, Base.Bound: BinaryInteger, Base.Bound: FrameworkToolboxCompatible {
    /// Offsets the range by the specified value.
    ///
    /// - Parameter offset: The offset to shift.
    /// - Returns: The new range.
    public func shifted(by offset: Base.Bound) -> Base {
        .init(uncheckedBounds: (base.lowerBound + offset, base.upperBound + offset))
    }

    /// Offsets the range by the specified value.
    ///
    /// - Parameter offset: The offset to shift.
    public mutating func shift(by offset: Base.Bound) {
        base = shifted(by: offset)
    }

    /// Splits the range into an array of evenly spaced values.
    ///
    /// The returned array contains `amount` values starting at `lowerBound` and ending at `upperBound` (inclusive for the calculation).
    ///
    /// - Parameter amount: The number of segments to divide the range into.
    /// - Returns: An array of `Double` values evenly distributed across the range.
    ///
    /// Example usage:
    /// ```swift
    /// let values = (0...1).split(by: 5)
    /// // [0.0, 0.25, 0.5, 0.75, 1.0]
    /// ```
    public func split(by amount: Int) -> [Double] {
        guard amount > 1 else { return [Double(base.lowerBound), Double(base.upperBound)] }
        let step = Double(base.upperBound - base.lowerBound) / Double(amount)
        return (0 ... amount).map { Double(base.lowerBound) + Double($0) * step }
    }

    /// The midpoint value between the `lowerBound` and `upperBound`, using integer division.
    public var center: Base.Bound {
        (base.lowerBound + base.upperBound) / 2
    }
}

extension FrameworkToolbox where Base: RangeRepresentable, Base.Bound: BinaryFloatingPoint, Base.Bound: FrameworkToolboxCompatible {
    /// Shifts the range by the specified offset value.
    ///
    /// - Parameter offset: The offset to shift.
    /// - Returns: The new range.
    func shifted(by offset: Base.Bound) -> Base {
        .init(uncheckedBounds: (base.lowerBound + offset, base.upperBound + offset))
    }

    func sdsds() {
        // (0.0...1.0).
    }

    /// Offsets the range by the specified value.
    ///
    /// - Parameter offset: The offset to shift.
    mutating func shift(by offset: Base.Bound) {
        base = shifted(by: offset)
    }

    /// Splits the range into an array of evenly spaced values.
    ///
    /// The returned array contains `amount` values starting at `lowerBound` and ending at `upperBound` (inclusive for the calculation).
    ///
    /// - Parameter amount: The number of segments to divide the range into.
    /// - Returns: An array of `Bound` values evenly distributed across the range.
    ///
    /// Example usage:
    /// ```swift
    /// let values = (0.0...1.0).split(by: 5)
    /// // [0.0, 0.25, 0.5, 0.75, 1.0]
    /// ```
    func split(by amount: Int) -> [Base.Bound] {
        guard amount > 1 else { return amount == 1 ? [base.lowerBound] : [] }
        let step = (base.upperBound - base.lowerBound) / Base.Bound(amount - 1)
        return (0 ..< amount).map { base.lowerBound + Base.Bound($0) * step }
    }

    /// The midpoint value between the `lowerBound` and `upperBound`.
    var center: Base.Bound {
        (base.lowerBound + base.upperBound) / 2.0
    }
}

extension RangeRepresentable where Bound: BinaryInteger, Bound.Stride: SignedInteger {
    /// values of of the range.
    public var values: [Bound] {
        self is ClosedRange<Bound> ? (lowerBound ... upperBound).map { $0 } : (lowerBound ..< upperBound).map { $0 }
    }
}

extension FrameworkToolbox where Base: Sequence, Base.Element: RangeRepresentable, Base.Element: FrameworkToolboxCompatible {
    /// Returns the union of all ranges in the sequence.
    public var union: Base.Element? {
        guard let min = min, let max = max else { return nil }
        return .init(uncheckedBounds: (min, max))
    }

    /// Returns the minimum lower bound in the sequence.
    public var min: Base.Element.Bound? {
        base.map(\.lowerBound).min()
    }

    /// Returns the maximum upper bound in the sequence.
    public var max: Base.Element.Bound? {
        base.map(\.upperBound).max()
    }
}
