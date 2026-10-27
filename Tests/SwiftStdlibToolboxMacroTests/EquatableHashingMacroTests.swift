import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

// `_EquatableHashing` is a pair of overloads, and which one runs is decided by
// overload resolution on whether the type is `Hashable` — which the test harness
// does not do, since it maps a name straight to an implementation. So each
// implementation is mapped and checked on its own here; the choice between them
// is exercised by real compilation, in `EquatableHashingConsistencyTests` and in
// every client that applies `@Equatable` to a type that is not `Hashable`.
@Suite
struct EquatableHashingMacroTests {

    @Test func hashableTypeGetsTheHashFunctionMatchingEquality() {
        assertMacro(["_EquatableHashing": MatchingHashFunctionMacro.self]) {
            """
            nonisolated extension Note: Equatable {
                @_EquatableHashing(Note.self, members: ["identifier", "title"])
                nonisolated public static func == (lhs: Note, rhs: Note) -> Bool {
                    lhs.identifier == rhs.identifier && lhs.title == rhs.title
                }
            }
            """
        } expansion: {
            """
            nonisolated extension Note: Equatable {
                nonisolated public static func == (lhs: Note, rhs: Note) -> Bool {
                    lhs.identifier == rhs.identifier && lhs.title == rhs.title
                }

                nonisolated public func hash(into hasher: inout Hasher) {
                    hasher.combine(identifier)
                    hasher.combine(title)
                }
            }
            """
        }
    }

    @Test func hashableTypeComparingNothingHashesNothing() {
        assertMacro(["_EquatableHashing": MatchingHashFunctionMacro.self]) {
            """
            nonisolated extension Empty: Equatable {
                @_EquatableHashing(Empty.self, members: [])
                nonisolated public static func == (lhs: Empty, rhs: Empty) -> Bool {
                    true
                }
            }
            """
        } expansion: {
            """
            nonisolated extension Empty: Equatable {
                nonisolated public static func == (lhs: Empty, rhs: Empty) -> Bool {
                    true
                }

                nonisolated public func hash(into hasher: inout Hasher) {
                }
            }
            """
        }
    }

    @Test func otherTypesGetNothing() {
        assertMacro(["_EquatableHashing": NoHashFunctionMacro.self]) {
            """
            nonisolated extension Note: Equatable {
                @_EquatableHashing(Note.self, members: ["identifier", "title"])
                nonisolated public static func == (lhs: Note, rhs: Note) -> Bool {
                    lhs.identifier == rhs.identifier && lhs.title == rhs.title
                }
            }
            """
        } expansion: {
            """
            nonisolated extension Note: Equatable {
                nonisolated public static func == (lhs: Note, rhs: Note) -> Bool {
                    lhs.identifier == rhs.identifier && lhs.title == rhs.title
                }
            }
            """
        }
    }
}
