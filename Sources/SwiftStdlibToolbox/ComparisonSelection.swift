import FrameworkToolbox

// MARK: - Sort ordering

/// The direction a key-path-driven sort runs in.
///
/// Deliberately not `Foundation.SortOrder` — `SwiftStdlibToolbox` and everything
/// below it stay clear of Foundation. Deliberately not `ComparisonResult`
/// either: that one carries an `.equal` case, which is not a direction.
@frozen
public enum SortOrdering {
    case ascending
    case descending
}

// MARK: - Selecting a comparison definition
//
// `ComparableBuildable.comparableDefinition` is the one definition `<` and `==`
// use. A type may declare any number of further definitions as plain static
// properties carrying an explicit `@ComparableBuilder<Self>`, and the methods
// below pick one by a key path rooted at the *metatype*:
//
//     struct Person: ComparableBuildable {
//         static var comparableDefinition: some ComparisonStep<Self> { compare(\.name) }
//
//         @ComparableBuilder<Self>
//         static var byAge: some ComparisonStep<Self> {
//             compare(\.age)
//             compare(\.name)
//         }
//     }
//
//     people.box.sorted(using: \.byAge)
//
// Note what is *not* required: the element does not have to conform to
// `ComparableBuildable`. The constraint is only that the selected property's
// type is a `ComparisonStep` over the element type, so a type that has no single
// natural ordering — and therefore should not be `Comparable` at all — can still
// carry definitions and be sorted by them.
//
// ## Every one of these applies the key path inside the comparison closure
//
// Hoisting it into a local first is the same code, the same behaviour, no
// diagnostic — and 5.7x slower:
//
//     let step = Base.Element.self[keyPath: definitionKeyPath]     // ← do not
//     return base.sorted { step.compare($0, $1) == .ascending }
//
// `KeyPathProjector::getLiteralKeyPath` (swift/lib/SILOptimizer/Utils) looks
// through ownership instructions, `upcast` and `open_existential_ref`, then
// requires the operand to *be* the `keypath` instruction. A key path that
// reached the use site through a local, a closure capture, or a struct field is
// a `struct_extract` / `load` / block argument by then, the `dyn_cast` fails,
// and `tryOptimizeKeypathApplication` gives up — every comparison then pays a
// `swift_getAtKeyPath` runtime call. Applying it in the closure keeps the
// literal in view, which is exactly the shape SE-0249 generates for
// `map(\.name)`: `{ [$kp$ = \Root.name] in $0[keyPath: $kp$] }`.
//
// It looks like the closure rebuilds the whole step tree per comparison. It does
// not — that is the version that folds away completely.
//
// Two measured traps: `@_transparent` instead of `@inline(__always)` takes the
// same code from 23 ms to 272 ms (it inlines in the mandatory pipeline and
// disturbs the later folding), and forcing the *definition's* getter inline
// changes nothing. `ComparableBuildableBenchmarks` pins the gap.

extension FrameworkToolbox where Base: Sequence {
    /// The sequence's elements, sorted by the definition at `definitionKeyPath`.
    ///
    /// - Parameter definitionKeyPath: A key path to a static comparison
    ///   definition on the element type, e.g. `\.byAge`.
    @inlinable
    @inline(__always)
    public func sorted<Step: ComparisonStep>(
        using definitionKeyPath: KeyPath<Base.Element.Type, Step>
    ) -> [Base.Element] where Step.T == Base.Element {
        base.sorted {
            Base.Element.self[keyPath: definitionKeyPath].compare($0, $1) == .ascending
        }
    }

    /// The smallest element by the definition at `definitionKeyPath`,
    /// or `nil` if the sequence is empty.
    @inlinable
    @inline(__always)
    public func min<Step: ComparisonStep>(
        using definitionKeyPath: KeyPath<Base.Element.Type, Step>
    ) -> Base.Element? where Step.T == Base.Element {
        base.min {
            Base.Element.self[keyPath: definitionKeyPath].compare($0, $1) == .ascending
        }
    }

    /// The largest element by the definition at `definitionKeyPath`,
    /// or `nil` if the sequence is empty.
    @inlinable
    @inline(__always)
    public func max<Step: ComparisonStep>(
        using definitionKeyPath: KeyPath<Base.Element.Type, Step>
    ) -> Base.Element? where Step.T == Base.Element {
        base.max {
            Base.Element.self[keyPath: definitionKeyPath].compare($0, $1) == .ascending
        }
    }

    /// Whether the sequence is already in ascending order by the definition at
    /// `definitionKeyPath`. An empty or single-element sequence is sorted.
    @inlinable
    @inline(__always)
    public func isSorted<Step: ComparisonStep>(
        using definitionKeyPath: KeyPath<Base.Element.Type, Step>
    ) -> Bool where Step.T == Base.Element {
        var iterator = base.makeIterator()
        guard var previousElement = iterator.next() else { return true }
        while let currentElement = iterator.next() {
            let result = Base.Element.self[keyPath: definitionKeyPath]
                .compare(previousElement, currentElement)
            if result == .descending { return false }
            previousElement = currentElement
        }
        return true
    }
}

extension FrameworkToolbox where Base: MutableCollection, Base: RandomAccessCollection {
    /// Sorts the collection in place by the definition at `definitionKeyPath`.
    @inlinable
    @inline(__always)
    public mutating func sort<Step: ComparisonStep>(
        using definitionKeyPath: KeyPath<Base.Element.Type, Step>
    ) where Step.T == Base.Element {
        base.sort {
            Base.Element.self[keyPath: definitionKeyPath].compare($0, $1) == .ascending
        }
    }
}

// The two methods below are reached through the *element's* own `.box`, so the
// type has to conform to `FrameworkToolboxCompatible` — unlike the sequence
// methods above, where the `.box` belongs to the collection.

extension FrameworkToolbox {
    /// Compares this value against `other` using the definition at
    /// `definitionKeyPath`.
    @inlinable
    @inline(__always)
    public func compare<Step: ComparisonStep>(
        to other: Base,
        using definitionKeyPath: KeyPath<Base.Type, Step>
    ) -> ComparisonResult where Step.T == Base {
        Base.self[keyPath: definitionKeyPath].compare(base, other)
    }

    /// Whether this value sorts before `other` under the definition at
    /// `definitionKeyPath`.
    @inlinable
    @inline(__always)
    public func isLess<Step: ComparisonStep>(
        than other: Base,
        using definitionKeyPath: KeyPath<Base.Type, Step>
    ) -> Bool where Step.T == Base {
        Base.self[keyPath: definitionKeyPath].compare(base, other) == .ascending
    }
}

// MARK: - Sorting by a property key path
//
// No comparison definition and no `ComparableBuildable` conformance involved —
// any sequence whose elements have a `Comparable` property can use these. The
// key path arrives as an argument and is applied directly in the closure, which
// is already the shape the optimizer folds.

extension FrameworkToolbox where Base: Sequence {
    /// The sequence's elements, sorted by one `Comparable` property.
    ///
    /// - Parameters:
    ///   - propertyKeyPath: A key path to the property to order by.
    ///   - ordering: Ascending by default.
    @inlinable
    @inline(__always)
    public func sorted<Value: Comparable>(
        by propertyKeyPath: KeyPath<Base.Element, Value>,
        _ ordering: SortOrdering = .ascending
    ) -> [Base.Element] {
        switch ordering {
        case .ascending:
            return base.sorted { $0[keyPath: propertyKeyPath] < $1[keyPath: propertyKeyPath] }
        case .descending:
            // Reversing the operands rather than the result keeps equal elements
            // in their original relative order, which reversing the sorted array
            // would not.
            return base.sorted { $1[keyPath: propertyKeyPath] < $0[keyPath: propertyKeyPath] }
        }
    }
}

extension FrameworkToolbox where Base: MutableCollection, Base: RandomAccessCollection {
    /// Sorts the collection in place by one `Comparable` property.
    @inlinable
    @inline(__always)
    public mutating func sort<Value: Comparable>(
        by propertyKeyPath: KeyPath<Base.Element, Value>,
        _ ordering: SortOrdering = .ascending
    ) {
        switch ordering {
        case .ascending:
            base.sort { $0[keyPath: propertyKeyPath] < $1[keyPath: propertyKeyPath] }
        case .descending:
            base.sort { $1[keyPath: propertyKeyPath] < $0[keyPath: propertyKeyPath] }
        }
    }
}
