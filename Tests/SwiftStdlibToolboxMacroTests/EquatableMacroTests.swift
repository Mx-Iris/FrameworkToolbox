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
                let name: String
                let age: Int
            }

            extension User: Equatable {
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
                let id: UUID
                let name: String
                var cache: String = ""
            }

            extension User: Equatable {
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
                let id: Int
                let name: String
            }

            extension User: Equatable {
                nonisolated public static func == (lhs: User, rhs: User) -> Bool {
                    lhs.id == rhs.id && lhs.name == rhs.name
                }
            }

            extension User {
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
                let name: String
                let id: UUID
            }

            extension Item: Equatable {
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

            extension Empty: Equatable {
                nonisolated public static func == (lhs: Empty, rhs: Empty) -> Bool {
                    true
                }
            }
            """
        }
    }
}
