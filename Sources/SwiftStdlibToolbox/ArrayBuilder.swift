@resultBuilder
public enum ArrayBuilder<Element> {
    @inlinable
    public static func buildPartialBlock(first: Element) -> [Element] { [first] }

    @inlinable
    public static func buildPartialBlock(first: [Element]) -> [Element] { first }

    @inlinable
    public static func buildPartialBlock(accumulated: [Element], next: Element) -> [Element] { accumulated + [next] }

    @inlinable
    public static func buildPartialBlock(accumulated: [Element], next: [Element]) -> [Element] { accumulated + next }

    /// Empty block
    @inlinable
    public static func buildBlock() -> [Element] { [] }

    /// Empty partial block. Useful for switch cases to represent no elements.
    @inlinable
    public static func buildPartialBlock(first: Void) -> [Element] { [] }

    /// Impossible partial block. Useful for fatalError().
    @inlinable
    public static func buildPartialBlock(first: Never) -> [Element] {}

    /// Block for an 'if' condition.
    @inlinable
    public static func buildIf(_ element: [Element]?) -> [Element] { element ?? [] }

    /// Block for an 'if' condition which also have an 'else' branch.
    @inlinable
    public static func buildEither(first: [Element]) -> [Element] { first }

    /// Block for the 'else' branch of an 'if' condition.
    @inlinable
    public static func buildEither(second: [Element]) -> [Element] { second }

    /// Block for an array of elements. Useful for 'for' loops.
    @inlinable
    public static func buildArray(_ components: [[Element]]) -> [Element] { components.flatMap { $0 } }
}

extension Array {
    @inlinable
    public init(@ArrayBuilder<Element> _ builder: () -> [Element]) {
        self.init(builder())
    }
}
