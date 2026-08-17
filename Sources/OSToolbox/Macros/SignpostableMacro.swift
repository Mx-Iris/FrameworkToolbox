#if canImport(os)

import os.log
import os.signpost
import FrameworkToolbox

/// Automatically generates signpost infrastructure for the annotated declaration.
///
/// The signpost counterpart of `@Loggable`, and deliberately shaped the same way:
/// it generates members directly, requires no protocol conformance, and adapts to
/// what it is attached to.
///
/// - On `struct`, `class`, `enum`, or `actor`: emits stored properties for the
///   signposter and its `OSLog`, evaluated once per type at first access.
/// - On `protocol`: emits both **protocol requirements** and a **sibling
///   extension** with default implementations, so each conforming type gets its
///   own signposter keyed by its runtime metatype identity.
///
/// > Note: As with `@Loggable`, a Swift language restriction prevents attaching
/// > this to an `extension`. Attach it to the type or protocol instead.
///
/// ## Coexisting with `@Loggable`
///
/// The two are designed to be applied together — a type that logs usually also
/// wants to measure — so none of the members generated here collide with
/// `@Loggable`'s. That is a hard constraint rather than a coincidence: two member
/// macros emitting the same member name is an `invalid redeclaration`.
///
/// | `@Loggable` generates | `@Signpostable` generates |
/// |---|---|
/// | `subsystem` / `category` | `signpostSubsystem` / `signpostCategory` |
/// | `_osLog` / `logger` | `_signpostLog` / `signposter` |
/// | `_osLog(for:)` / `logger(for:)` | `_signpostLog(for:)` / `signposter(for:)` |
/// | — | `makeSignpostID()` / `makeSignpostID(from:)` |
///
/// A subsystem/category pair resolves to the same underlying `OSLog` whichever
/// macro reached it, so annotating with both does not double the log handles.
///
/// - Parameters:
///   - accessLevel: The access level for generated members. Defaults to `.private`.
///   - asProtocolRequirement: Only meaningful on a `protocol`. When `true` (the
///     default), requirements are emitted so conforming types may override them.
///     When `false`, only the default-implementation extension is emitted and the
///     members are effectively frozen for all conformers.
///   - subsystem: The subsystem string literal. Defaults to `nil`, which uses
///     `"<TypeName>"`. As with `@Loggable`, there is no bundle-identifier
///     fallback on purpose: deriving one would name `Bundle` in the expansion,
///     and the expansion lands in the caller's file.
///   - category: Override the auto-generated category with a string literal.
///     Defaults to `nil`, which generates `"<TypeName>"`.
///
/// To have signposts show up in Instruments' default track, use the system's
/// points-of-interest category — either for the whole type or per call site:
///
///     @Signpostable(category: "PointsOfInterest")
///     struct Launch { }
///
///     @Signpostable
///     struct Launch {
///         func run() { #signpost(.event, category: .pointsOfInterest, "launched") }
///     }
///
/// Example — concrete type:
///
///     @Signpostable
///     struct SyncService { }
///
///     // Expands to:
///     // struct SyncService {
///     //     private nonisolated static var signpostCategory: String { "SyncService" }
///     //     private nonisolated static var signpostSubsystem: String { "SyncService" }
///     //     private nonisolated static let _signpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)
///     //     @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
///     //     private nonisolated static let signposter = os.OSSignposter(logHandle: _signpostLog)
///     //     …
///     // }
@attached(member, names: named(_signpostLog), named(signpostCategory), named(signpostSubsystem), named(signposter), named(makeSignpostID))
@attached(extension, names: named(_signpostLog), named(signpostCategory), named(signpostSubsystem), named(signposter), named(makeSignpostID))
public macro Signpostable(
    _ accessLevel: AccessLevel = .private,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
) = #externalMacro(module: "OSToolboxMacros", type: "SignpostableMacro")

/// Overload of `@Signpostable` that exposes the `asProtocolRequirement` switch
/// (see the parameter documentation on the main `@Signpostable` declaration).
@attached(member, names: named(_signpostLog), named(signpostCategory), named(signpostSubsystem), named(signposter), named(makeSignpostID))
@attached(extension, names: named(_signpostLog), named(signpostCategory), named(signpostSubsystem), named(signposter), named(makeSignpostID))
public macro Signpostable(
    _ accessLevel: AccessLevel = .private,
    asProtocolRequirement: Bool,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
) = #externalMacro(module: "OSToolboxMacros", type: "SignpostableMacro")

#endif
