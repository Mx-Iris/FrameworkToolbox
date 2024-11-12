@resultBuilder
public enum DictionaryBuilder<Key: Hashable, Value> {
    public typealias Element = (Key, Value)
    
    public static func buildPartialBlock(first: Element) -> [Element] { [first] }

    public static func buildPartialBlock(first: [Element]) -> [Element] { first }

    public static func buildPartialBlock(accumulated: [Element], next: Element) -> [Element] { accumulated + [next] }

    public static func buildPartialBlock(accumulated: [Element], next: [Element]) -> [Element] { accumulated + next }

    public static func buildBlock() -> [Element] { [] }

    public static func buildPartialBlock(first: Void) -> [Element] { [] }

    public static func buildPartialBlock(first: Never) -> [Element] {}

    public static func buildIf(_ element: [Element]?) -> [Element] { element ?? [] }

    public static func buildEither(first: [Element]) -> [Element] { first }

    public static func buildEither(second: [Element]) -> [Element] { second }

    public static func buildArray(_ components: [[Element]]) -> [Element] { components.flatMap { $0 } }
}

extension Dictionary {
    public init(@DictionaryBuilder<Key, Value> _ builder: () -> [(Key, Value)]) {
        self.init(uniqueKeysWithValues: builder())
    }
}
