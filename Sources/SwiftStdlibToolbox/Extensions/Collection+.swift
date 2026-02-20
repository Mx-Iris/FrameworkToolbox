import FrameworkToolbox

extension FrameworkToolbox where Base: Collection, Base.Index == Int {
    @inlinable public subscript(safe index: Base.Index) -> Base.Element? {
        get {
            guard index >= 0, index < base.count else { return nil }
            return base[index]
        }
    }
}

extension FrameworkToolbox where Base: MutableCollection, Base.Index == Int {
    @inlinable public subscript(safe index: Base.Index) -> Base.Element? {
        set {
            guard index >= 0, index < base.count, let newValue else { return }
            base[index] = newValue
        }
        get {
            guard index >= 0, index < base.count else { return nil }
            return base[index]
        }
    }
}

// MARK: - First / Last N Elements

extension FrameworkToolbox where Base: Collection {
    /// Returns a subsequence containing the first elements up to the specified count.
    ///
    /// - Parameter amount: The number of elements to return.
    @inlinable
    public func first(_ amount: Int) -> Base.SubSequence {
        guard !base.isEmpty, amount > 0 else { return base.dropFirst(base.count) }
        return base.dropLast(Swift.max(0, base.count - amount))
    }

    /// Returns a subsequence containing the last elements up to the specified count.
    ///
    /// - Parameter amount: The number of elements to return.
    @inlinable
    public func last(_ amount: Int) -> Base.SubSequence {
        guard !base.isEmpty, amount > 0 else { return base.dropFirst(base.count) }
        return base.dropFirst(Swift.max(0, base.count - amount))
    }
}

// MARK: - Chunking

extension FrameworkToolbox where Base: Collection, Base.Index == Int {
    /// Splits the collection into arrays of the specified size.
    ///
    /// Any remaining elements are added to a separate chunk.
    ///
    /// ```swift
    /// [1,2,3,4,5,6,7,8,9].box.chunked(size: 3) // [[1,2,3], [4,5,6], [7,8,9]]
    /// [1,2,3,4,5,6,7,8,9].box.chunked(size: 2) // [[1,2], [3,4], [5,6], [7,8], [9]]
    /// ```
    ///
    /// - Parameter size: The size of each chunk.
    @inlinable
    public func chunked(size: Int) -> [[Base.Element]] {
        let size = Swift.max(size, 1)
        return stride(from: 0, to: base.count, by: size).map {
            Array(base[$0 ..< Swift.min($0 + size, base.count)])
        }
    }

    /// Splits the collection into the specified number of chunks.
    ///
    /// ```swift
    /// [1,2,3,4,5,6,7,8,9].box.chunked(amount: 3) // [[1,2,3], [4,5,6], [7,8,9]]
    /// [1,2,3,4,5,6,7,8,9].box.chunked(amount: 2) // [[1,2,3,4,5], [6,7,8,9]]
    /// ```
    ///
    /// - Parameter amount: The number of chunks.
    @inlinable
    public func chunked(amount: Int) -> [[Base.Element]] {
        let amount = Swift.max(1, Swift.min(amount, base.count))
        let chunkSize = base.count / amount
        let remainder = base.count % amount

        var start = base.startIndex
        return (0..<amount).reduce(into: []) { chunks, i in
            let thisChunkSize = chunkSize + (i < remainder ? 1 : 0)
            let end = start + thisChunkSize
            chunks.append(Array(base[start..<end]))
            start = end
        }
    }
}
