/// Makes a structure an `OptionSet` whose options are the cases of its nested
/// `Flag` enumeration, the raw value of each case being the position of its
/// bit.
///
/// Write the flags once, as cases, and the rest of the option set is
/// generated from them:
///
/// ```swift
/// @FlagSet
/// public struct Permissions: Codable, Hashable, Sendable {
///     public enum Flag: Int, CaseIterable, Sendable {
///         /// The holder can read the resource.
///         case read = 0
///         case write = 1
///         case execute = 2
///     }
/// }
/// ```
///
/// expands to:
///
/// ```swift
/// nonisolated public let rawValue: Int
///
/// @inlinable nonisolated public init(rawValue: Int) {
///     self.rawValue = rawValue
/// }
///
/// @inlinable nonisolated public init(_ flag: Flag) {
///     self.init(rawValue: 1 << flag.rawValue)
/// }
///
/// /// The holder can read the resource.
/// nonisolated public static let read = Self(.read)
/// nonisolated public static let write = Self(.write)
/// nonisolated public static let execute = Self(.execute)
/// ```
///
/// together with `extension Permissions: OptionSet {}` when the structure
/// does not declare the conformance itself. `Codable`, `Hashable` and
/// `Sendable` stay the caller's to declare; a declared `Codable` encodes the
/// set as its raw value.
///
/// Each static is generated from its case, so the two cannot disagree. A
/// case's documentation comment, its `@available` attributes and any `#if`
/// around it are carried over to its static, and the enumeration's own
/// `@available` goes on everything that mentions it.
///
/// `rawValue` has the raw type of `Flag`. A position that is negative, or
/// that does not fit in that type — `1 << 64` is `0` for an `Int` — would
/// make its flag an empty set, so such a position is reported on its case.
/// `Int` and `UInt` are checked as 64 bits wide, which they are everywhere
/// but on arm64_32 watchOS.
///
/// > Important: When the raw value is persisted or sent to another process,
/// > each case's position is part of that format. Write every position out,
/// > never reuse a retired one, and pin the shipped values with a test: an
/// > implicit raw value moves when a case is inserted above it.
///
/// > Note: Nothing this macro generates can be named inside the arguments of
/// > an attached macro, because name lookup there skips macro expansions:
/// > `@Test(arguments: [Permissions.read])` does not compile. Pass the `Flag`
/// > cases instead and build the set with `init(_:)` in the function body.
@attached(member, names: named(rawValue), named(init), arbitrary)
@attached(extension, conformances: OptionSet)
public macro FlagSet() = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "FlagSetMacro"
)
