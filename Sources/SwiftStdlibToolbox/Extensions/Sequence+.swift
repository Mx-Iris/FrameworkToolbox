import FrameworkToolbox

// MARK: - Sum

extension FrameworkToolbox where Base: Sequence, Base.Element: AdditiveArithmetic {
    /// The total sum of all values in the sequence. Returns `.zero` if the sequence is empty.
    @inlinable
    public func sum() -> Base.Element {
        base.reduce(.zero, +)
    }
}

// MARK: - Average

extension FrameworkToolbox where Base: Collection, Base.Element: BinaryFloatingPoint {
    /// The average value of all values in the collection. Returns `.zero` if empty.
    @inlinable
    public func average() -> Base.Element {
        guard !base.isEmpty else { return .zero }
        return base.reduce(.zero, +) / Base.Element(base.count)
    }
}

extension FrameworkToolbox where Base: Collection, Base.Element: BinaryInteger {
    /// The average value of all values in the collection as `Double`. Returns `0` if empty.
    @inlinable
    public func average() -> Double {
        guard !base.isEmpty else { return 0 }
        return base.map { Double($0) }.reduce(0, +) / Double(base.count)
    }
}

// MARK: - Contains

extension FrameworkToolbox where Base: Sequence, Base.Element: Hashable {
    /// Returns `true` if the sequence contains any of the given elements.
    ///
    /// - Parameter elements: The elements to find in the sequence.
    @inlinable
    public func contains<S: Sequence>(any elements: S) -> Bool where S.Element == Base.Element {
        let set = Set(base)
        return elements.contains { set.contains($0) }
    }

    /// Returns `true` if the sequence contains all of the given elements.
    ///
    /// - Parameter elements: The elements to find in the sequence.
    @inlinable
    public func contains<S: Sequence>(all elements: S) -> Bool where S.Element == Base.Element {
        let set = Set(base)
        return elements.allSatisfy { set.contains($0) }
    }
}

extension FrameworkToolbox where Base: Sequence, Base.Element: Equatable {
    /// Returns `true` if the sequence contains any of the given elements.
    ///
    /// - Parameter elements: The elements to find in the sequence.
    @inlinable
    public func contains<S: Sequence>(any elements: S) -> Bool where S.Element == Base.Element {
        elements.contains { base.contains($0) }
    }

    /// Returns `true` if the sequence contains all of the given elements.
    ///
    /// - Parameter elements: The elements to find in the sequence.
    @inlinable
    public func contains<S: Sequence>(all elements: S) -> Bool where S.Element == Base.Element {
        elements.allSatisfy { base.contains($0) }
    }
}

// MARK: - Grouping & Keying

extension FrameworkToolbox where Base: Sequence {
    /// Groups elements by the key returned from the given closure.
    ///
    /// - Parameter keyForValue: A closure that returns a key for each element.
    /// - Returns: A dictionary of grouped elements.
    @inlinable
    public func grouped<Key: Hashable>(by keyForValue: (Base.Element) throws -> Key) rethrows -> [Key: [Base.Element]] {
        try Dictionary(grouping: base, by: keyForValue)
    }

    /// Creates a dictionary keyed by the results of the given closure.
    ///
    /// If duplicate keys are encountered, the latest value is kept.
    ///
    /// - Parameter keyForValue: A closure that returns a key for each element.
    @inlinable
    public func keyed<Key: Hashable>(by keyForValue: (Base.Element) throws -> Key) rethrows -> [Key: Base.Element] {
        try base.reduce(into: [:]) { result, element in
            let key = try keyForValue(element)
            result[key] = element
        }
    }
}

// MARK: - KeyPath Aggregation

extension FrameworkToolbox where Base: Sequence {
    /// Returns the element with the minimum value for the given key path.
    ///
    /// - Parameter keyPath: The key path to the comparable value.
    @inlinable
    public func min<V: Comparable>(by keyPath: KeyPath<Base.Element, V>) -> Base.Element? {
        base.min { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }

    /// Returns the element with the maximum value for the given key path.
    ///
    /// - Parameter keyPath: The key path to the comparable value.
    @inlinable
    public func max<V: Comparable>(by keyPath: KeyPath<Base.Element, V>) -> Base.Element? {
        base.max { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }
}

// MARK: - Type Filtering

extension FrameworkToolbox where Base: Sequence {
    /// Returns the first element that is of the specified type.
    ///
    /// - Parameter type: The type to search for.
    @inlinable
    public func first<T>(ofType type: T.Type) -> T? {
        base.lazy.compactMap { $0 as? T }.first
    }

    /// Returns all elements that are of the specified type.
    ///
    /// - Parameter type: The type to filter for.
    @inlinable
    public func all<T>(ofType type: T.Type) -> [T] {
        base.compactMap { $0 as? T }
    }
}
