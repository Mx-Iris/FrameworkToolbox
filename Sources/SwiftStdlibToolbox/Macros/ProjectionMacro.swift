//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

/// Generates a property for every `@ProjectionFunction` in the enumeration,
/// each pulling one shared value out of every case, whatever that case carries.
///
/// Cases often hold unrelated payload types that nevertheless share a concept
/// — a name, an identifier, an owning account. Asking for it normally means
/// writing the same `switch` again for each such concept.
///
/// ```swift
/// @Projection enum Target {
///     case user(User)
///     case session(Session?)
///     case anonymous
///
///     @ProjectionFunction
///     static func id(_ value: some Identifiable<String>) -> String {
///         value.id
///     }
/// }
/// ```
///
/// expands to:
///
/// ```swift
/// var id: String? {
///     switch self {
///     case .user(let payload): Self.id(payload)
///     case .session(let payload?): Self.id(payload)
///     default: nil
///     }
/// }
/// ```
///
/// A case is matched when it carries exactly as many values as the projection
/// function takes — zero included. An optional payload is unwrapped in the
/// pattern, so the projection function never has to be generic over
/// optionality; the argument labels come from the projection function rather
/// than from the case.
///
/// Mark as many functions as you like: each one gets its own property.
///
/// > Note: The projection function is named by the marker on the function
/// > itself rather than by a string here, because a macro argument cannot
/// > reference a member of the very type the macro is attached to — that is a
/// > circular reference — and a generic function cannot be passed as a value
/// > at all. See `Documentations/EnumMacros.md`.
@attached(member, names: arbitrary)
public macro Projection() = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "ProjectionMacro"
)

/// Marks the `static func` that ``Projection()`` builds a property from. The
/// property takes the function's name.
///
/// - Parameter flatten: Whether to avoid a double optional when this function
///   returns an optional. Defaults to `true`. Pass `false` to keep
///   "no case matched" distinguishable from "matched, and the projection was
///   nil".
@attached(peer)
public macro ProjectionFunction(flatten: Bool = true) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "ProjectionFunctionMacro"
)
