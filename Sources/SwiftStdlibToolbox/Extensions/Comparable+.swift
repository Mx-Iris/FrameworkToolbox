import FrameworkToolbox

extension FrameworkToolbox where Base: Comparable {
    /// Clamps the value to the specified closed range.
    ///
    /// - Parameter range: The closed range to clamp the value to.
    /// - Returns: The clamped value.
    public func clamped(to range: ClosedRange<Base>) -> Base {
        max(range.lowerBound, min(base, range.upperBound))
    }

    /// Clamps the value to the specified range.
    ///
    /// - Parameter range: The closed range to clamp the value to.
    /// - Returns: The clamped value.

    public func clamped(to range: Range<Base>) -> Base where Base: BinaryInteger {
        max(range.lowerBound, min(base, range.upperBound - 1))
    }

    /// Clamps the value to the specified partial range.
    ///
    /// - Parameter range: The partial range to clamp the value to.
    /// - Returns: The clamped value.
    public func clamped(to range: PartialRangeFrom<Base>) -> Base {
        max(range.lowerBound, base)
    }

    /// Clamps the value to the specified partial range.
    ///
    /// - Parameter range: The partial range to clamp the value to.
    /// - Returns: The clamped value.
    public func clamped(to range: PartialRangeUpTo<Base>) -> Base {
        min(range.upperBound, base)
    }

    /// Clamps the value to the specified minimum value.
    ///
    /// - Parameter minValue: The minimum value to clamp the value to.
    /// - Returns: The clamped value.
    public func clamped(min minValue: Base) -> Base {
        max(minValue, base)
    }

    /// Clamps the value to the specified maximum value.
    ///
    /// - Parameter maxValue: The maximum value to clamp the value to.
    /// - Returns: The clamped value.
    public func clamped(max maxValue: Base) -> Base {
        min(maxValue, base)
    }

    /// Clamps the value to the specified closed range.
    ///
    /// - Parameter range: The closed range to clamp the value to.
    public mutating func clamp(to range: ClosedRange<Base>) {
        base = clamped(to: range)
    }

    /// Clamps the value to specified partial range.
    ///
    /// - Parameter range: The partial range to clamp the value to.
    public mutating func clamp(to range: PartialRangeFrom<Base>) {
        base = clamped(to: range)
    }

    /// Clamps the value to specified partial range.
    ///
    /// - Parameter range: The partial range to clamp the value to.
    public mutating func clamp(to range: PartialRangeUpTo<Base>) {
        base = clamped(to: range)
    }

    /// Clamps the value to a minimum value.
    ///
    /// - Parameter minValue: The minimum value to clamp the value to.
    public mutating func clamp(min minValue: Base) {
        base = clamped(min: minValue)
    }

    /// Clamps the value to a maximum value.
    ///
    /// - Parameter maxValue: The maximum value to clamp the value to.
    public mutating func clamp(max maxValue: Base) {
        base = clamped(max: maxValue)
    }
}

extension FrameworkToolbox where Base: Sequence, Base.Element: Comparable, Base.Element: FrameworkToolboxCompatible {
    public typealias Element = Base.Element
    
    /// Clamps the elements of the sequence to the specified range.
    ///
    /// - Parameter range: The range to clamp the elements to.
    /// - Returns: The clamped elements.
    public func clamped(to range: ClosedRange<Element>) -> [Element] {
        base.map { $0.box.clamped(to: range) }
    }

    /// Clamps the elements of the sequence to the specified range.
    ///
    /// - Parameter range: The range to clamp the elements to.
    /// - Returns: The clamped elements.
    public func clamped(to range: PartialRangeFrom<Element>) -> [Element] {
        base.map { $0.box.clamped(to: range) }
    }

    /// Clamps the elements of the sequence to the specified range.
    ///
    /// - Parameter range: The range to clamp the elements to.
    /// - Returns: The clamped elements.
    public func clamped(to range: PartialRangeUpTo<Element>) -> [Element] {
        base.map { $0.box.clamped(to: range) }
    }

    /// Clamps the elements of the sequence to the specified minimum value.
    ///
    /// - Parameter maxValue: The minimum value to clamp the elements to.
    /// - Returns: The clamped elements.
    public func clamped(min minValue: Element) -> [Element] {
        base.map { $0.box.clamped(min: minValue) }
    }

    /// Clamps the elements of the sequence to the specified maximum value.
    ///
    /// - Parameter maxValue: The maximum value to clamp the elements to.
    /// - Returns: The clamped elements.
    public func clamped(max maxValue: Element) -> [Element] {
        base.map { $0.box.clamped(max: maxValue) }
    }
}

extension FrameworkToolbox where Base: Sequence, Base: RangeReplaceableCollection, Base.Element: Comparable, Base.Element: FrameworkToolboxCompatible {
    /// Clamps the elements of the sequence to the specified range.
    ///
    /// - Parameter range: The range to clamp the elements to.
    public mutating func clamp(to range: ClosedRange<Element>) {
        base = Base(clamped(to: range))
    }

    /// Clamps the elements of the sequence to the specified range.
    ///
    /// - Parameter range: The range to clamp the elements to.
    public mutating func clamp(to range: PartialRangeFrom<Element>) {
        base = Base(clamped(to: range))
    }

    /// Clamps the elements of the sequence to the specified range.
    ///
    /// - Parameter range: The range to clamp the elements to.
    public mutating func clamp(to range: PartialRangeUpTo<Element>) {
        base = Base(clamped(to: range))
    }

    /// Clamps the elements of the sequence to the specified minimum value.
    ///
    /// - Parameter maxValue: The minimum value to clamp the elements to.
    /// - Returns: The clamped elements.
    public mutating func clamp(min minValue: Element) {
        base = Base(clamped(min: minValue))
    }

    /// Clamps the elements of the sequence to the specified maximum value.
    ///
    /// - Parameter maxValue: The maximum value to clamp the elements to.
    public mutating func clamp(max maxValue: Element) {
        base = Base(clamped(max: maxValue))
    }
}
