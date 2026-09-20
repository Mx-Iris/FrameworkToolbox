//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

/// Generates a zero-argument static property for every case whose associated
/// values can all be filled in without the caller saying anything.
///
/// Swift requires arguments at the call site for any case with associated
/// values, even when every one of them is optional or has a default. That is
/// what stands between you and writing `.recurring`.
///
/// ```swift
/// @DefaultedCases enum Task {
///     case recurring(interval: Int = 60, tag: String? = nil)
///     case quick
///     case custom(deadline: Date)
/// }
/// ```
///
/// expands to:
///
/// ```swift
/// static var recurring: Self {
///     .recurring(interval: 60, tag: nil)
/// }
/// ```
///
/// A parameter with a default argument uses it; an optional parameter without
/// one gets `nil`. Cases with no associated values (`.quick`) already work and
/// are skipped, as is any case holding a parameter that is neither optional nor
/// defaulted (`.custom(deadline:)`) — there is nothing to fill it with.
///
/// > Note: An optional associated value must be spelled with `?`. A macro
/// > matches spellings rather than resolving types, so `Optional<Int>` is not
/// > recognized as optional; writing it produces a warning saying so.
@attached(member, names: arbitrary)
public macro DefaultedCases() = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "DefaultedCasesMacro"
)
