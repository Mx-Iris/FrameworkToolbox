import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

// The harness hands an extension macro an empty `conformingTo:` list, so the
// `OptionSet` conformance never appears in these snapshots. That it is added,
// and only when the structure does not declare it, is covered by real
// compilation: `FlagSetTests` in `SwiftStdlibToolboxTests`.
@Suite(.macros(["FlagSet": FlagSetMacro.self]))
struct FlagSetMacroTests {

    // MARK: - What is generated

    @Test func generatesTheSetFromTheFlagCases() {
        assertMacro {
            """
            @FlagSet
            public struct Permissions: Codable, Hashable, Sendable {
                public enum Flag: Int, CaseIterable, Sendable {
                    /// The holder can read the resource.
                    case read = 0
                    case write = 1
                }
            }
            """
        } expansion: {
            """
            public struct Permissions: Codable, Hashable, Sendable {
                public enum Flag: Int, CaseIterable, Sendable {
                    /// The holder can read the resource.
                    case read = 0
                    case write = 1
                }

                nonisolated public let rawValue: Int

                @inlinable nonisolated public init(rawValue: Int) {
                    self.rawValue = rawValue
                }

                @inlinable nonisolated public init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                /// The holder can read the resource.
                nonisolated public static let read = Self(.read)

                nonisolated public static let write = Self(.write)
            }
            """
        }
    }

    @Test func leavesTheMembersOfAnInternalSetUnmarked() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Flag: UInt8 {
                    /// Shared by both.
                    case first, second
                    case `default`
                }
            }
            """
        } expansion: {
            """
            struct Options {
                enum Flag: UInt8 {
                    /// Shared by both.
                    case first, second
                    case `default`
                }

                nonisolated let rawValue: UInt8

                nonisolated init(rawValue: UInt8) {
                    self.rawValue = rawValue
                }

                nonisolated init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                /// Shared by both.
                nonisolated static let first = Self(.first)

                /// Shared by both.
                nonisolated static let second = Self(.second)

                nonisolated static let `default` = Self(.`default`)
            }
            """
        }
    }

    @Test func keepsTheFlagInitializerNoMoreVisibleThanFlag() {
        assertMacro {
            """
            @FlagSet
            public struct Options {
                private enum Flag: Int {
                    case first
                }
            }
            """
        } expansion: {
            """
            public struct Options {
                private enum Flag: Int {
                    case first
                }

                nonisolated public let rawValue: Int

                @inlinable nonisolated public init(rawValue: Int) {
                    self.rawValue = rawValue
                }

                nonisolated private init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                nonisolated public static let first = Self(.first)
            }
            """
        }
    }

    @Test func carriesAvailabilityOverToWhatNamesTheFlag() {
        assertMacro {
            """
            @FlagSet
            public struct Features {
                @available(macOS 14, *)
                public enum Flag: Int {
                    case base = 0
                    @available(*, deprecated, message: "Retired")
                    case legacy = 1
                }
            }
            """
        } expansion: {
            """
            public struct Features {
                @available(macOS 14, *)
                public enum Flag: Int {
                    case base = 0
                    @available(*, deprecated, message: "Retired")
                    case legacy = 1
                }

                nonisolated public let rawValue: Int

                @inlinable nonisolated public init(rawValue: Int) {
                    self.rawValue = rawValue
                }

                @available(macOS 14, *)
                @inlinable nonisolated public init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                @available(macOS 14, *)
                nonisolated public static let base = Self(.base)

                @available(macOS 14, *)
                @available(*, deprecated, message: "Retired")
                nonisolated public static let legacy = Self(.legacy)
            }
            """
        }
    }

    @Test func reproducesConditionalCompilationAroundACase() {
        assertMacro {
            """
            @FlagSet
            struct Platforms {
                enum Flag: Int {
                    case shared = 0
                    #if os(macOS)
                    case desktop = 1
                    #else
                    case handheld = 1
                    #endif
                    #if DEBUG
                    static let debugOnly = 0
                    #endif
                }
            }
            """
        } expansion: {
            """
            struct Platforms {
                enum Flag: Int {
                    case shared = 0
                    #if os(macOS)
                    case desktop = 1
                    #else
                    case handheld = 1
                    #endif
                    #if DEBUG
                    static let debugOnly = 0
                    #endif
                }

                nonisolated let rawValue: Int

                nonisolated init(rawValue: Int) {
                    self.rawValue = rawValue
                }

                nonisolated init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                nonisolated static let shared = Self(.shared)

                #if os(macOS)
                nonisolated static let desktop = Self(.desktop)
                #else
                nonisolated static let handheld = Self(.handheld)
                #endif
            }
            """
        }
    }

    // MARK: - What is reported

    @Test func rejectsAnythingButAStructure() {
        assertMacro {
            """
            @FlagSet
            enum Options {
                enum Flag: Int {
                    case first
                }
            }
            """
        } diagnostics: {
            """
            @FlagSet
            ╰─ 🛑 '@FlagSet' must be applied to a struct
            enum Options {
                enum Flag: Int {
                    case first
                }
            }
            """
        }
    }

    @Test func requiresANestedFlagEnumeration() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Option: Int {
                    case first
                }
            }
            """
        } diagnostics: {
            """
            @FlagSet
            struct Options {
                   ┬──────
                   ╰─ 🛑 '@FlagSet' needs an 'enum Flag' declared in the body of 'Options', whose cases are the flags of the set
                enum Option: Int {
                    case first
                }
            }
            """
        }
    }

    @Test func offersARawTypeWhenFlagHasNone() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Flag {
                    case first
                }
            }
            """
        } diagnostics: {
            """
            @FlagSet
            struct Options {
                enum Flag {
                     ┬───
                     ╰─ 🛑 'Flag' needs an integer raw type: the raw value of each case is the position of its bit
                        ✏️ add 'Int' as the raw type
                    case first
                }
            }
            """
        } fixes: {
            """
            @FlagSet
            struct Options {
                enum Flag: Int {
                    case first
                }
            }
            """
        } expansion: {
            """
            struct Options {
                enum Flag: Int {
                    case first
                }

                nonisolated let rawValue: Int

                nonisolated init(rawValue: Int) {
                    self.rawValue = rawValue
                }

                nonisolated init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                nonisolated static let first = Self(.first)
            }
            """
        }
    }

    @Test func offersARawTypeWhenFlagStartsWithAProtocol() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Flag: CaseIterable, Sendable {
                    case first
                }
            }
            """
        } diagnostics: {
            """
            @FlagSet
            struct Options {
                enum Flag: CaseIterable, Sendable {
                     ┬───
                     ╰─ 🛑 'Flag' needs an integer raw type: the raw value of each case is the position of its bit
                        ✏️ add 'Int' as the raw type
                    case first
                }
            }
            """
        } fixes: {
            """
            @FlagSet
            struct Options {
                enum Flag: Int, CaseIterable, Sendable {
                    case first
                }
            }
            """
        } expansion: {
            """
            struct Options {
                enum Flag: Int, CaseIterable, Sendable {
                    case first
                }

                nonisolated let rawValue: Int

                nonisolated init(rawValue: Int) {
                    self.rawValue = rawValue
                }

                nonisolated init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                nonisolated static let first = Self(.first)
            }
            """
        }
    }

    @Test func rejectsARawTypeThatIsNotAnInteger() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Flag: String {
                    case first
                }
            }
            """
        } diagnostics: {
            """
            @FlagSet
            struct Options {
                enum Flag: String {
                           ┬─────
                           ╰─ 🛑 'Flag' needs an integer raw type, not 'String': the raw value of each case is the position of its bit
                    case first
                }
            }
            """
        }
    }

    @Test func reportsPositionsOutsideTheRawType() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Flag: Int8 {
                    case low = -1
                    case high = 7
                    case pastTheEnd
                }
            }
            """
        } diagnostics: {
            """
            @FlagSet
            struct Options {
                enum Flag: Int8 {
                    case low = -1
                               ┬─
                               ╰─ 🛑 bit position -1 is negative; '1 << -1' is 0, so 'low' would be an empty set
                    case high = 7
                    case pastTheEnd
                         ┬─────────
                         ╰─ 🛑 bit position 8 does not fit in 'Int8', which has 8 bits; '1 << 8' is 0, so 'pastTheEnd' would be an empty set
                }
            }
            """
        }
    }

    @Test func checksIntAsSixtyFourBitsWide() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Flag: Swift.Int {
                    case last = 63
                    case pastTheEnd = 64
                }
            }
            """
        } diagnostics: {
            """
            @FlagSet
            struct Options {
                enum Flag: Swift.Int {
                    case last = 63
                    case pastTheEnd = 64
                                      ┬─
                                      ╰─ 🛑 bit position 64 does not fit in 'Swift.Int', which has 64 bits; '1 << 64' is 0, so 'pastTheEnd' would be an empty set
                }
            }
            """
        }
    }

    @Test func doesNotCheckARawTypeItCannotRecognize() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Flag: Position {
                    case far = 100
                }
            }
            """
        } expansion: {
            """
            struct Options {
                enum Flag: Position {
                    case far = 100
                }

                nonisolated let rawValue: Position

                nonisolated init(rawValue: Position) {
                    self.rawValue = rawValue
                }

                nonisolated init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                nonisolated static let far = Self(.far)
            }
            """
        }
    }

    @Test func doesNotGuessAPositionThatDependsOnTheActiveBranch() {
        assertMacro {
            """
            @FlagSet
            struct Options {
                enum Flag: UInt8 {
                    case first = 6
                    #if DEBUG
                    case debug
                    #endif
                    case afterTheBranch
                }
            }
            """
        } expansion: {
            """
            struct Options {
                enum Flag: UInt8 {
                    case first = 6
                    #if DEBUG
                    case debug
                    #endif
                    case afterTheBranch
                }

                nonisolated let rawValue: UInt8

                nonisolated init(rawValue: UInt8) {
                    self.rawValue = rawValue
                }

                nonisolated init(_ flag: Flag) {
                    self.init(rawValue: 1 << flag.rawValue)
                }

                nonisolated static let first = Self(.first)

                #if DEBUG
                nonisolated static let debug = Self(.debug)
                #endif

                nonisolated static let afterTheBranch = Self(.afterTheBranch)
            }
            """
        }
    }
}
