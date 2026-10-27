/// Source: https://github.com/ordo-one/equatable

/// A macro that automatically generates an `Equatable` conformance for structs.
///
/// This macro creates a standard equality implementation by comparing all stored properties
/// that aren't explicitly marked to be skipped with `@EquatableIgnored.
/// Properties with SwiftUI property wrappers (like `@State`, `@ObservedObject`, etc.)
///
/// Structs with arbitary closures are not supported unless they are marked explicitly with `@EquatableIgnoredUnsafeClosure` -
/// meaning that they are safe because they don't  influence rendering of the view's body.
///
/// Usage:
/// ```swift
/// import Equatable
/// import SwiftUI
///
/// @Equatable
/// struct ProfileView: View {
///     var username: String   // Will be compared
///     @State private var isLoading = false           // Automatically skipped
///     @ObservedObject var viewModel: ProfileViewModel // Automatically skipped
///     @EquatableIgnored var cachedValue: String? // This property will be excluded
///     @EquatableIgnoredUnsafeClosure var onTap: () -> Void // This closure is safe and will be ignored in comparison
///     let id: UUID // will be compared first for shortcircuiting equality checks
///
///     var body: some View {
///         VStack {
///             Text(username)
///             if isLoading {
///                 ProgressView()
///             }
///         }
///     }
/// }
/// ```
///
/// The generated extension will implement the `==` operator with property comparisons
/// ordered for optimal performance (e.g., IDs and simple types first):
/// ```swift
/// extension ProfileView: Equatable {
///     nonisolated public static func == (lhs: ProfileView, rhs: ProfileView) -> Bool {
///         lhs.id == rhs.id && lhs.username == rhs.username
///     }
/// }
/// ```
///
/// If the type is marked as conforming to `Hashable` the compiler synthesized `Hashable` implementation will not be correct.
/// That's why the `@Equatable` macro will also generate a `Hashable` implementation for the type that is aligned with the `Equatable` implementation.
///
/// ```swift
/// import Equatable
/// @Equatable
/// struct User: Hashable {
///     let id: Int
///     @EquatableIgnored var name = ""
/// }
/// ```
///
/// Expanded:
/// ```swift
/// nonisolated extension User: Equatable {
///     nonisolated public static func == (lhs: User, rhs: User) -> Bool {
///         lhs.id == rhs.id
///     }
/// }
/// nonisolated extension User {
///     nonisolated public func hash(into hasher: inout Hasher) {
///         hasher.combine(id)
///     }
/// }
/// ```
///
/// Whether the type is `Hashable` is the compiler's call, wherever the
/// conformance comes from. A `Hashable` named in the type's own inheritance
/// clause, in any spelling (`Swift.Hashable`, `nonisolated Hashable`,
/// `Hashable & Sendable`), gets the `hash(into:)` above directly. Otherwise the
/// generated `==` carries `_EquatableHashing`, which writes the same
/// `hash(into:)` exactly when the type turns out to be `Hashable` — through an
/// extension elsewhere, a protocol that refines `Hashable`, or a superclass —
/// and nothing otherwise. A conditional conformance
/// (`extension Pair: Hashable where First: Hashable`) is the one case it cannot
/// cover: the extension the macro writes into carries no such constraint, so
/// the compiler synthesizes `hash(into:)` over every stored property there.
///
/// The extensions are `nonisolated` so that in a module whose default isolation
/// is `MainActor` the conformance stays usable off the main actor, as its
/// `nonisolated` witnesses already are.
///
/// Every compared member also gets a check, attached by the macro, that has the
/// compiler confirm the member's type conforms to `Equatable` — `Hashable` when
/// the inheritance clause names `Hashable`. A member that does not is reported
/// on its own line, with a fix that applies `@EquatableIgnored`, instead of only
/// as an error inside the generated `==`.
@attached(extension, conformances: Equatable, names: named(==), named(hash(into:)))
@attached(memberAttribute)
public macro Equatable() = #externalMacro(module: "SwiftStdlibToolboxMacros", type: "EquatableMacro")

// MARK: - Member checks

// `@Equatable` attaches one of these to every member its `==` compares, because
// whether a member's type conforms to `Equatable` is something only the compiler
// knows. Each is a pair of overloads differing in nothing but a constraint, so
// the compiler chooses between them as it would between two functions: a
// conforming type matches both and the constrained one wins; any other type
// matches only the one that reports the member — on the member itself, with a
// fix. They generate nothing.
//
// The two argument labels keep the forms apart. Unlabelled, `Int.self` would
// also match the by-value overloads, as a metatype value.

/// Checks that a member written with a type annotation can be compared.
@_documentation(visibility: private)
@attached(peer)
public macro _EquatableMemberCheck<Member>(type: Member.Type) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "UncomparableMemberMacro"
)

@_documentation(visibility: private)
@attached(peer)
public macro _EquatableMemberCheck<Member: Equatable>(type: Member.Type) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "ComparableMemberMacro"
)

/// Checks that a member written without a type annotation can be compared,
/// from its initial value, whose type the compiler infers here as it does for
/// the property.
@_documentation(visibility: private)
@attached(peer)
public macro _EquatableMemberCheck<Member>(initialValue: Member) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "UncomparableMemberMacro"
)

@_documentation(visibility: private)
@attached(peer)
public macro _EquatableMemberCheck<Member: Equatable>(initialValue: Member) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "ComparableMemberMacro"
)

/// The checks for a type declared `Hashable`, whose generated `hash(into:)`
/// combines every compared member.
@_documentation(visibility: private)
@attached(peer)
public macro _HashableMemberCheck<Member>(type: Member.Type) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "UncomparableMemberMacro"
)

@_documentation(visibility: private)
@attached(peer)
public macro _HashableMemberCheck<Member: Hashable>(type: Member.Type) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "ComparableMemberMacro"
)

@_documentation(visibility: private)
@attached(peer)
public macro _HashableMemberCheck<Member>(initialValue: Member) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "UncomparableMemberMacro"
)

@_documentation(visibility: private)
@attached(peer)
public macro _HashableMemberCheck<Member: Hashable>(initialValue: Member) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "ComparableMemberMacro"
)

// MARK: - Hashing

// Whether a type is `Hashable` cannot be read off its declaration: the
// conformance may sit in an extension elsewhere, come through a protocol that
// refines `Hashable`, or be inherited. Listing `Hashable` among `@Equatable`'s
// `conformances:` to have the compiler report it backfires. Before expanding,
// the compiler records a placeholder conformance for every listed protocol, and
// while that placeholder exists a conformance merely implied by a refined
// protocol is never recorded — so the type stopped being `Hashable` at all.
//
// So when the inheritance clause does not name `Hashable`, the generated `==`
// carries `_EquatableHashing`, and overload resolution decides: a `Hashable`
// type matches both overloads and the constrained one wins, writing the
// `hash(into:)` that combines exactly the members `==` compares, in the same
// order; any other type matches only the one that writes nothing. The member
// names travel as string literals, which are not type-checked, so a member
// whose type does not compile cannot drag this attribute into the error.

/// Writes nothing: the type is not `Hashable`.
@_documentation(visibility: private)
@attached(peer, names: named(hash(into:)))
public macro _EquatableHashing<Subject>(_ subject: Subject.Type, members: [String]) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "NoHashFunctionMacro"
)

/// Writes the `hash(into:)` that agrees with `==`: the type is `Hashable`.
@_documentation(visibility: private)
@attached(peer, names: named(hash(into:)))
public macro _EquatableHashing<Subject: Hashable>(_ subject: Subject.Type, members: [String]) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "MatchingHashFunctionMacro"
)

/// A peer macro that marks properties to be ignored in `Equatable` conformance generation.
///
/// This macro allows developers to explicitly exclude specific properties from the equality comparison
/// when using the `@Equatable` macro. It performs validation to ensure it's used correctly.
///
/// Usage:
/// ```swift
/// @Equatable
/// struct User {
///     let id: UUID
///     let name: String
///     @EquatableIgnored var temporaryCache: [String: Any] // This property will be excluded
/// }
/// ```
///
/// This macro cannot be applied to:
/// - Non-property declarations
/// - Closure properties
/// - Properties already marked with `@Binding`
@attached(peer)
public macro EquatableIgnored() = #externalMacro(module: "SwiftStdlibToolboxMacros", type: "EquatableIgnoredMacro")

/// A macro that makes closure properties safely participate in `Equatable` conformance.
///
/// ## Overview
///
/// Closures aro not diffable by default and not allowed  when applying the `@Equatable` macro.
/// Apply the `@EquatableIgnoredUnsafeClosure` attribute to closure which are safe to be excluded from equality comparisons.
/// Only closures that do not capture value types on call site and do not influence rendering of the view's body are safe to be marked with this attribute.
///
/// ## Exammple - Safe Usage of `@EquatableIgnoredUnsafeClosure`
///
/// Apply the `@EquatableIgnoredUnsafeClosure` attribute to closure properties in your type:
///
/// ```swift
/// struct UserActions: Equatable {
///     let id: UUID
///     let name: String
///
///     @EquatableIgnoredUnsafeClosure
///     var onTap: () -> Void
/// }
///
/// struct ContentView: View {
///     var body: some View {
///         UserActions(id: UUID(), name: "Example") {
///             print("User tapped") // This closure does not capture value types on call site
///                                  // and does not influence rendering of `UserActions` view's body.
///         }
///     }
/// }
/// ```
///
/// In this example, `onTap` will be excluded from equality comparisons, allowing the `UserActions` instances to be properly compared based only on `id` and `name`.
///
/// ## Example - Unsafe Usage of `@EquatableIgnoredUnsafeClosure`
/// ```swift
/// struct DemoView: View {
///     @State var enabled = false
///
///     var body: some View {
///         Text("Enabled? \(enabled)")
///         .onTapGesture(perform: {
///             enabled.toggle()
///         })
///         Content(enabled: enabled)
///     }
/// }
///
/// struct Content: View {
///     var enabled: Bool
///     var body: some View {
///         ViewTakesClosure(
///         label: "This view takes a closure",
///         onTapGesture: {
///             // This will always print "enabled? False", because this `ViewTakesClosure`
///             // is never re-rendered (its Equatable inputs never change).
///             // The closure captures the initial value of `enabled=false`.
///             print("enabled? \(enabled)")
///         })
///     }
/// }
///
/// @Equabable
/// struct ViewTakesClosure: View {
///     let label: String
///     @EquatableIgnoredUnsafeClosure let onTapGesture: () -> Void
///
///     var body: some View {
///         Text(label)
///         .onTapGesture(perform: onTapGesture)
///     }
/// }
/// ```
///
/// In this example `ViewTakesClosure`'s closure captures the `enabled` value on callsite and since it's marked with `@EquatableIgnoredUnsafeClosure`
/// it will not cause a re-render when the value of `enabled` changes. The closure will always print the initial value of `enabled` which is an incorrect behavior.
///
/// ## Requirements
///
/// - The decorated property must be a closure type
@attached(peer)
public macro EquatableIgnoredUnsafeClosure() = #externalMacro(module: "SwiftStdlibToolboxMacros", type: "EquatableIgnoredUnsafeClosureMacro")
