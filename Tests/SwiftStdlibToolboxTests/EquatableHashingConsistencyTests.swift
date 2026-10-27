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
// still decides that the type conforms.
extension ExtensionHashableNote: Hashable {}

// Hashable only by way of a protocol that refines it — named in the type's own
// inheritance clause, in an extension, and on a class. These did not compile at
// all: listing `Hashable` among the macro's conformances kept the compiler from
// recording a conformance that is merely implied.
protocol HashableRecord: Hashable {}

@Equatable
struct RefinedHashableNote: HashableRecord {
    let identifier: Int
    @EquatableIgnored var note: String
}

@Equatable
struct ExtensionRefinedHashableNote {
    let identifier: Int
    @EquatableIgnored var note: String
}

extension ExtensionRefinedHashableNote: HashableRecord {}

@Equatable
final class RefinedHashableHandle: HashableRecord {
    let identifier: Int
    @EquatableIgnored var note: String

    init(identifier: Int, note: String) {
        self.identifier = identifier
        self.note = note
    }
}

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

    @Test func hashableThroughARefinedProtocol() {
        let first = RefinedHashableNote(identifier: 1, note: "first")
        let second = RefinedHashableNote(identifier: 1, note: "second")
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(Set([first, second]).count == 1)
    }

    @Test func hashableThroughARefinedProtocolDeclaredInAnExtension() {
        let first = ExtensionRefinedHashableNote(identifier: 1, note: "first")
        let second = ExtensionRefinedHashableNote(identifier: 1, note: "second")
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test func classHashableThroughARefinedProtocol() {
        let first = RefinedHashableHandle(identifier: 1, note: "first")
        let second = RefinedHashableHandle(identifier: 1, note: "second")
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }
}
