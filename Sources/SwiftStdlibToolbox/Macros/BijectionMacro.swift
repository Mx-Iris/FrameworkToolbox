//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

/// Generates the initializer that inverts a computed property mapping each
/// enumeration case to a distinct value.
///
/// Useful wherever a raw-value-backed enumeration will not do: binary
/// encodings, string representations, or a case list that also needs the
/// synthesized `Comparable` conformance a raw value would interfere with.
///
/// ```swift
/// enum Code {
///     case ok
///     case notFound
///
///     @Bijection var status: Int {
///         switch self {
///         case .ok: 200
///         case .notFound: 404
///         }
///     }
/// }
/// ```
///
/// expands to:
///
/// ```swift
/// init?(_ $value: borrowing Int) {
///     switch $value {
///     case 200: self = .ok
///     case 404: self = .notFound
///     default: return nil
///     }
/// }
/// ```
///
/// The getter must hold a single `switch` block whose cases are each a single
/// expression with `return` elided, which is what makes the mapping readable
/// in reverse.
///
/// The generated initializer mirrors the property's access level and other
/// modifiers, and carries over `@available`, `@backDeployed`, `@inlinable`,
/// `@inline` and `@usableFromInline`.
///
/// - Parameters:
///   - label: The argument label of the generated initializer. Defaults to
///     none.
///   - where: The name of a protocol to make the generated initializer generic
///     over, instead of taking the property's own type — `where:
///     "StringProtocol"` on a `String` property accepts a `Substring` without
///     a copy.
@attached(peer, names: named(init))
public macro Bijection(
    label: String = "_",
    where: String? = nil
) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "BijectionMacro"
)
