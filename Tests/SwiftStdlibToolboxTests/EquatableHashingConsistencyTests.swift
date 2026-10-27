import SwiftStdlibToolbox
import Testing

// For a Hashable type `@Equatable` writes `hash(into:)` itself, over exactly the
// members its `==` compares. When it misses that the type is Hashable, the
// compiler synthesizes `hash(into:)` over every stored property instead, and two
// values the macro calls equal hash differently — which breaks `Set` and
// `Dictionary` with no diagnostic anywhere. Each type below declares Hashable in
// a way the macro used to overlook.

@Equatable
struct QualifiedHashableNote: Swift.Hashable {
    let identifier: Int
    @EquatableIgnored var note: String
}

@Equatable
struct ComposedHashableNote: Hashable & Sendable {
    let identifier: Int
    @EquatableIgnored var note: String
}

@Equatable
struct ExtensionHashableNote {
    let identifier: Int
    @EquatableIgnored var note: String
}

// Declared away from the type, where the macro cannot see it. The compiler
// still tells the macro the type conforms.
extension ExtensionHashableNote: Hashable {}

@Suite("@Equatable hashes exactly what it compares")
struct EquatableHashingConsistencyTests {
    @Test func moduleQualifiedHashable() {
        let first = QualifiedHashableNote(identifier: 1, note: "first")
        let second = QualifiedHashableNote(identifier: 1, note: "second")
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test func hashableInAComposition() {
        let first = ComposedHashableNote(identifier: 1, note: "first")
        let second = ComposedHashableNote(identifier: 1, note: "second")
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test func hashableDeclaredInAnExtension() {
        let first = ExtensionHashableNote(identifier: 1, note: "first")
        let second = ExtensionHashableNote(identifier: 1, note: "second")
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }
}
