import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros([
    "Equatable": EquatableMacro.self,
    "EquatableIgnored": EquatableIgnoredMacro.self,
    "EquatableIgnoredUnsafeClosure": EquatableIgnoredUnsafeClosureMacro.self,
]))
struct EquatableMacroTests {

    @Test func basicStruct() {
        assertMacro {
            """
            @Equatable
            struct User {
                let name: String
                let age: Int
            }
            """
        } expansion: {
            """
            struct User {
                @SwiftStdlibToolbox._EquatableMemberCheck(type: String.self)
                let name: String
                @SwiftStdlibToolbox._EquatableMemberCheck(type: Int.self)
                let age: Int
            }

            nonisolated extension User: Equatable {
                nonisolated public static func == (lhs: User, rhs: User) -> Bool {
                    lhs.age == rhs.age && lhs.name == rhs.name
                }
            }
            """
        }
    }

    @Test func withIgnoredProperty() {
        assertMacro {
            """
            @Equatable
            struct User {
                let id: UUID
                let name: String
                @EquatableIgnored var cache: String = ""
            }
            """
        } expansion: {
            """
            struct User {
                @SwiftStdlibToolbox._EquatableMemberCheck(type: UUID.self)
                let id: UUID
                @SwiftStdlibToolbox._EquatableMemberCheck(type: String.self)
                let name: String
                var cache: String = ""
            }

            nonisolated extension User: Equatable {
                nonisolated public static func == (lhs: User, rhs: User) -> Bool {
                    lhs.id == rhs.id && lhs.name == rhs.name
                }
            }
            """
        }
    }

    @Test func withHashable() {
        assertMacro {
            """
            @Equatable
            struct User: Hashable {
                let id: Int
                let name: String
            }
            """
        } expansion: {
            """
            struct User: Hashable {
                @SwiftStdlibToolbox._HashableMemberCheck(type: Int.self)
                let id: Int
                @SwiftStdlibToolbox._HashableMemberCheck(type: String.self)
                let name: String
            }

            nonisolated extension User: Equatable {
                nonisolated public static func == (lhs: User, rhs: User) -> Bool {
                    lhs.id == rhs.id && lhs.name == rhs.name
                }
            }

            nonisolated extension User {
                nonisolated public func hash(into hasher: inout Hasher) {
                    hasher.combine(id)
                    hasher.combine(name)
                }
            }
            """
        }
    }

    @Test func idPropertySortedFirst() {
        assertMacro {
            """
            @Equatable
            struct Item {
                let name: String
                let id: UUID
            }
            """
        } expansion: {
            """
            struct Item {
                @SwiftStdlibToolbox._EquatableMemberCheck(type: String.self)
                let name: String
                @SwiftStdlibToolbox._EquatableMemberCheck(type: UUID.self)
                let id: UUID
            }

            nonisolated extension Item: Equatable {
                nonisolated public static func == (lhs: Item, rhs: Item) -> Bool {
                    lhs.id == rhs.id && lhs.name == rhs.name
                }
            }
            """
        }
    }

    @Test func emptyStruct() {
        assertMacro {
            """
            @Equatable
            struct Empty {
            }
            """
        } expansion: {
            """
            struct Empty {
            }

            nonisolated extension Empty: Equatable {
                nonisolated public static func == (lhs: Empty, rhs: Empty) -> Bool {
                    true
                }
            }
            """
        }
    }

    // The markers may be spelled with their module. They stay unexpanded here
    // because the test harness only expands attributes written without one;
    // what matters is that `@Equatable` still recognises them and leaves both
    // properties out of the comparison.
    @Test func recognisesModuleQualifiedMarkers() {
        assertMacro {
            """
            @Equatable
            struct User {
                let id: UUID
                @SwiftStdlibToolbox.EquatableIgnored var cache: String = ""
                @SwiftStdlibToolbox.EquatableIgnoredUnsafeClosure var onTap: () -> Void
            }
            """
        } expansion: {
            """
            struct User {
                @SwiftStdlibToolbox._EquatableMemberCheck(type: UUID.self)
                let id: UUID
                @SwiftStdlibToolbox.EquatableIgnored var cache: String = ""
                @SwiftStdlibToolbox.EquatableIgnoredUnsafeClosure var onTap: () -> Void
            }

            nonisolated extension User: Equatable {
                nonisolated public static func == (lhs: User, rhs: User) -> Bool {
                    lhs.id == rhs.id
                }
            }
            """
        }
    }

    // Each of these declares Hashable, so each needs the `hash(into:)` that
    // agrees with `==`. Missing one leaves the compiler to hash every stored
    // property, including the ones `==` ignores.
    @Test func generatesHashingForEverySpellingOfHashable() {
        assertMacro {
            """
            @Equatable
            struct Qualified: Swift.Hashable {
                let id: Int
            }

            @Equatable
            struct Isolated: nonisolated Hashable {
                let id: Int
            }

            @Equatable
            struct Composed: Hashable & Sendable {
                let id: Int
            }
            """
        } expansion: {
            """
            struct Qualified: Swift.Hashable {
                @SwiftStdlibToolbox._HashableMemberCheck(type: Int.self)
                let id: Int
            }
            struct Isolated: nonisolated Hashable {
                @SwiftStdlibToolbox._HashableMemberCheck(type: Int.self)
                let id: Int
            }
            struct Composed: Hashable & Sendable {
                @SwiftStdlibToolbox._HashableMemberCheck(type: Int.self)
                let id: Int
            }

            nonisolated extension Qualified: Equatable {
                nonisolated public static func == (lhs: Qualified, rhs: Qualified) -> Bool {
                    lhs.id == rhs.id
                }
            }

            nonisolated extension Qualified {
                nonisolated public func hash(into hasher: inout Hasher) {
                    hasher.combine(id)
                }
            }

            nonisolated extension Isolated: Equatable {
                nonisolated public static func == (lhs: Isolated, rhs: Isolated) -> Bool {
                    lhs.id == rhs.id
                }
            }

            nonisolated extension Isolated {
                nonisolated public func hash(into hasher: inout Hasher) {
                    hasher.combine(id)
                }
            }

            nonisolated extension Composed: Equatable {
                nonisolated public static func == (lhs: Composed, rhs: Composed) -> Bool {
                    lhs.id == rhs.id
                }
            }

            nonisolated extension Composed {
                nonisolated public func hash(into hasher: inout Hasher) {
                    hasher.combine(id)
                }
            }
            """
        }
    }

    // `@SwiftUI.Binding` is the same wrapper as `@Binding`, and ignoring it is
    // refused for the same reason whichever way it is spelled.
    @Test func ignoredRejectsModuleQualifiedBinding() {
        assertMacro {
            """
            struct Row {
                @SwiftUI.Binding @EquatableIgnored var value: Int
            }
            """
        } diagnostics: {
            """
            struct Row {
                @SwiftUI.Binding @EquatableIgnored var value: Int
                                 ┬────────────────
                                 ╰─ 🛑 @EquatableIgnored cannot be applied to @Binding properties
            }
            """
        }
    }
}
