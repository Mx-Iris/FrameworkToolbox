@frozen public enum ComparisonResult {
    case ascending
    case descending
    case equal
}

// MARK: - Step protocol

/// A statically-typed comparison step. Every concrete step exposes its
/// own type to the type system, allowing the builder to fold a chain of
/// `compare(\.x)` calls into a nested generic struct that the optimizer
/// can fully inline.
public protocol ComparisonStep<T> {
    associatedtype T
    func compare(_ lhs: T, _ rhs: T) -> ComparisonResult
}

// MARK: - Leaf step types

@frozen
public struct EmptyComparisonStep<T>: ComparisonStep {
    @inlinable
    @inline(__always)
    public init() {}

    @inlinable
    @inline(__always)
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        return .equal
    }
}

@frozen
public struct KeyPathComparisonStep<T, V: Comparable>: ComparisonStep {
    @usableFromInline
    let keyPath: KeyPath<T, V>

    @inlinable
    @inline(__always)
    public init(_ keyPath: KeyPath<T, V>) {
        self.keyPath = keyPath
    }

    @inlinable
    @inline(__always)
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        let lhsValue = lhs[keyPath: keyPath]
        let rhsValue = rhs[keyPath: keyPath]
        if lhsValue < rhsValue {
            return .ascending
        }
        if rhsValue < lhsValue {
            return .descending
        }
        return .equal
    }
}

@frozen
public struct OptionalKeyPathComparisonStep<T, V: Comparable>: ComparisonStep {
    @usableFromInline
    let keyPath: KeyPath<T, V?>

    @inlinable
    @inline(__always)
    public init(_ keyPath: KeyPath<T, V?>) {
        self.keyPath = keyPath
    }

    @inlinable
    @inline(__always)
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        guard let lhsValue = lhs[keyPath: keyPath] else {
            if rhs[keyPath: keyPath] == nil {
                return .equal
            }
            return .ascending
        }
        guard let rhsValue = rhs[keyPath: keyPath] else {
            return .descending
        }
        if lhsValue < rhsValue {
            return .ascending
        }
        if rhsValue < lhsValue {
            return .descending
        }
        return .equal
    }
}

@frozen
public struct DescendingKeyPathComparisonStep<T, V: Comparable>: ComparisonStep {
    @usableFromInline
    let keyPath: KeyPath<T, V>

    @inlinable
    @inline(__always)
    public init(_ keyPath: KeyPath<T, V>) {
        self.keyPath = keyPath
    }

    @inlinable
    @inline(__always)
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        let lhsValue = lhs[keyPath: keyPath]
        let rhsValue = rhs[keyPath: keyPath]
        if rhsValue < lhsValue {
            return .ascending
        }
        if lhsValue < rhsValue {
            return .descending
        }
        return .equal
    }
}

@frozen
public struct CustomKeyPathComparisonStep<T, V>: ComparisonStep {
    @usableFromInline
    let keyPath: KeyPath<T, V>
    @usableFromInline
    let comparator: (V, V) -> ComparisonResult

    @inlinable
    @inline(__always)
    public init(_ keyPath: KeyPath<T, V>, _ comparator: @escaping (V, V) -> ComparisonResult) {
        self.keyPath = keyPath
        self.comparator = comparator
    }

    @inlinable
    @inline(__always)
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        return comparator(lhs[keyPath: keyPath], rhs[keyPath: keyPath])
    }
}

// MARK: - Combinator step types

/// Two steps in sequence; short-circuits on first non-equal result.
@frozen
public struct CompositeComparisonStep<T, First: ComparisonStep, Second: ComparisonStep>: ComparisonStep
where First.T == T, Second.T == T {
    @usableFromInline
    let first: First
    @usableFromInline
    let second: Second

    @inlinable
    @inline(__always)
    public init(first: First, second: Second) {
        self.first = first
        self.second = second
    }

    @inlinable
    @inline(__always)
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        let result = first.compare(lhs, rhs)
        if result != .equal {
            return result
        }
        return second.compare(lhs, rhs)
    }
}

/// Produced by `if/else` inside a builder.
@frozen
public enum EitherComparisonStep<T, First: ComparisonStep, Second: ComparisonStep>: ComparisonStep
where First.T == T, Second.T == T {
    case first(First)
    case second(Second)

    @inlinable
    @inline(__always)
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        switch self {
        case .first(let step):
            return step.compare(lhs, rhs)
        case .second(let step):
            return step.compare(lhs, rhs)
        }
    }
}

/// Produced by `if` (without `else`) inside a builder.
@frozen
public struct OptionalComparisonStep<T, Wrapped: ComparisonStep>: ComparisonStep
where Wrapped.T == T {
    @usableFromInline
    let wrapped: Wrapped?

    @inlinable
    @inline(__always)
    public init(_ wrapped: Wrapped?) {
        self.wrapped = wrapped
    }

    @inlinable
    @inline(__always)
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        guard let wrapped = wrapped else {
            return .equal
        }
        return wrapped.compare(lhs, rhs)
    }
}

/// Produced by `for` loops inside a builder. All elements must be the same
/// step type, which is the natural restriction of homogeneous loops.
@frozen
public struct ArrayComparisonStep<T, Element: ComparisonStep>: ComparisonStep
where Element.T == T {
    @usableFromInline
    let steps: ContiguousArray<Element>

    @inlinable
    public init(_ steps: ContiguousArray<Element>) {
        self.steps = steps
    }

    @inlinable
    public func compare(_ lhs: T, _ rhs: T) -> ComparisonResult {
        for step in steps {
            let result = step.compare(lhs, rhs)
            if result != .equal {
                return result
            }
        }
        return .equal
    }
}

// MARK: - Result builder

@resultBuilder
public struct ComparableBuilder<T> {
    @inlinable
    @inline(__always)
    public static func buildBlock() -> EmptyComparisonStep<T> {
        return EmptyComparisonStep()
    }

    @inlinable
    @inline(__always)
    public static func buildPartialBlock<S: ComparisonStep>(first: S) -> S
    where S.T == T {
        return first
    }

    @inlinable
    @inline(__always)
    public static func buildPartialBlock<Accumulated: ComparisonStep, Next: ComparisonStep>(
        accumulated: Accumulated,
        next: Next
    ) -> CompositeComparisonStep<T, Accumulated, Next>
    where Accumulated.T == T, Next.T == T {
        return CompositeComparisonStep(first: accumulated, second: next)
    }

    @inlinable
    @inline(__always)
    public static func buildEither<First: ComparisonStep, Second: ComparisonStep>(
        first: First
    ) -> EitherComparisonStep<T, First, Second>
    where First.T == T, Second.T == T {
        return .first(first)
    }

    @inlinable
    @inline(__always)
    public static func buildEither<First: ComparisonStep, Second: ComparisonStep>(
        second: Second
    ) -> EitherComparisonStep<T, First, Second>
    where First.T == T, Second.T == T {
        return .second(second)
    }

    @inlinable
    @inline(__always)
    public static func buildOptional<Wrapped: ComparisonStep>(
        _ step: Wrapped?
    ) -> OptionalComparisonStep<T, Wrapped>
    where Wrapped.T == T {
        return OptionalComparisonStep(step)
    }

    @inlinable
    public static func buildArray<Element: ComparisonStep>(
        _ components: [Element]
    ) -> ArrayComparisonStep<T, Element>
    where Element.T == T {
        return ArrayComparisonStep(ContiguousArray(components))
    }
}

// MARK: - ComparableBuildable protocol

/// Conforming types describe how to order themselves by combining
/// `ComparisonStep` instances through a result-builder DSL.
///
/// The requirement is annotated with `@ComparableBuilder<Self>`, so
/// step expressions are written directly inside the property's
/// braces:
///
/// ```swift
/// struct Foo: ComparableBuildable {
///     var a: Int
///     var b: Int
///
///     static var comparableDefinition: some ComparisonStep<Self> {
///         compare(\.a)
///         compare(\.b)
///     }
/// }
/// ```
///
/// The `<Self>` on the opaque return type cannot be omitted: the
/// result-builder body has no explicit `return`, so the compiler
/// cannot recover `Definition.T` from the builder alone — the
/// primary associated type has to be stated on the return type to
/// satisfy `Definition.T == Self`.
///
/// ## Use `static var`, not `static let`
///
/// `comparableDefinition` must be a computed property. Every step
/// type is `@frozen` with `@inlinable @inline(__always)` methods, so
/// when the step tree is constructed inside a computed property the
/// optimizer inlines every builder call, step initializer, and
/// nested `compare(_:_:)` into the `<` / `==` call site. The literal
/// `\.a` / `\.b` `KeyPath` expressions are still in view at that
/// point, so Swift's `KeyPath` optimization pass rewrites
/// `lhs[keyPath: \.a]` into a direct member access — making the
/// final SIL equivalent to a hand-written comparator.
///
/// A stored `static let` builds the tree once into a global. The
/// optimizer cannot constant-propagate the stored `KeyPath` fields
/// back to the use site, so every comparison goes through the
/// generic `KeyPath` subscript and pays roughly 5–10× over a
/// hand-written `Comparable` conformance. The legacy
/// `makeComparable { ... }` factory that enabled this form is
/// deprecated for the same reason.
public protocol ComparableBuildable: Comparable {
    associatedtype Definition: ComparisonStep<Self>
    @ComparableBuilder<Self>
    static var comparableDefinition: Definition { get }
}

// MARK: - Factory methods

extension ComparableBuildable {
    @inlinable
    @inline(__always)
    public static func compare<V: Comparable>(_ keyPath: KeyPath<Self, V>) -> KeyPathComparisonStep<Self, V> {
        return KeyPathComparisonStep(keyPath)
    }

    @inlinable
    @inline(__always)
    public static func compare<V: Comparable>(_ keyPath: KeyPath<Self, V?>) -> OptionalKeyPathComparisonStep<Self, V> {
        return OptionalKeyPathComparisonStep(keyPath)
    }

    @inlinable
    @inline(__always)
    public static func compareDescending<V: Comparable>(_ keyPath: KeyPath<Self, V>) -> DescendingKeyPathComparisonStep<Self, V> {
        return DescendingKeyPathComparisonStep(keyPath)
    }

    @inlinable
    @inline(__always)
    public static func compareCustom<V>(
        _ keyPath: KeyPath<Self, V>,
        _ comparator: @escaping (V, V) -> ComparisonResult
    ) -> CustomKeyPathComparisonStep<Self, V> {
        return CustomKeyPathComparisonStep(keyPath, comparator)
    }

    @available(*, deprecated, message: "Write step expressions directly inside `comparableDefinition`'s braces — the requirement carries `@ComparableBuilder<Self>`, so this wrapper is no longer needed.")
    @inlinable
    @inline(__always)
    public static func makeComparable<S: ComparisonStep>(
        @ComparableBuilder<Self> builder: () -> S
    ) -> S where S.T == Self {
        return builder()
    }
}

// MARK: - Comparable conformance

extension ComparableBuildable {
    @inlinable
    @inline(__always)
    public static func < (lhs: Self, rhs: Self) -> Bool {
        return comparableDefinition.compare(lhs, rhs) == .ascending
    }

    @inlinable
    @inline(__always)
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return comparableDefinition.compare(lhs, rhs) == .equal
    }
}
