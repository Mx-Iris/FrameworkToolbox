@resultBuilder
public enum DictionaryBuilder<Key: Hashable, Value> {
    public typealias Element = (Key, Value)
    
    @inlinable
    public static func buildPartialBlock(first: Element) -> [Element] { [first] }

    @inlinable
    public static func buildPartialBlock(first: [Element]) -> [Element] { first }

    @inlinable
    public static func buildPartialBlock(accumulated: [Element], next: Element) -> [Element] { accumulated + [next] }

    @inlinable
    public static func buildPartialBlock(accumulated: [Element], next: [Element]) -> [Element] { accumulated + next }

    @inlinable
    public static func buildBlock() -> [Element] { [] }

    @inlinable
    public static func buildPartialBlock(first: Void) -> [Element] { [] }

    @inlinable
    public static func buildPartialBlock(first: Never) -> [Element] {}

    @inlinable
    public static func buildIf(_ element: [Element]?) -> [Element] { element ?? [] }

    @inlinable
    public static func buildEither(first: [Element]) -> [Element] { first }

    @inlinable
    public static func buildEither(second: [Element]) -> [Element] { second }

    @inlinable
    public static func buildArray(_ components: [[Element]]) -> [Element] { components.flatMap { $0 } }
}

extension Dictionary {
    @inlinable
    public init(@DictionaryBuilder<Key, Value> _ builder: () -> [(Key, Value)]) {
        self.init(uniqueKeysWithValues: builder())
    }
    
    @inlinable
    public init(@DictionaryBuilder<Key, Value> _ builder: (_ keyType: Key.Type) -> [(Key, Value)]) {
        self.init(uniqueKeysWithValues: builder(Key.self))
    }
    
    @inlinable
    public init(@DictionaryBuilder<Key, Value> _ builder: (_ keyType: Key.Type, _ valueType: Value.Type) -> [(Key, Value)]) {
        self.init(uniqueKeysWithValues: builder(Key.self, Value.self))
    }
}
