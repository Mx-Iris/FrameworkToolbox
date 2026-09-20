//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

/// Generates the payload-free counterpart of an enumeration — its *tag* — and
/// a `tag` property returning the one that matches.
///
/// Reach for it when code needs to know *which case* a value is without caring
/// what the case carries: indexing, hashing, serializing, or a table keyed by
/// case.
///
/// ```swift
/// @CaseTag(backing: String.self) enum Action {
///     case start
///     case stop
///     case reset(Int?)
/// }
/// ```
///
/// expands to:
///
/// ```swift
/// enum ActionTag: String {
///     case start
///     case stop
///     case reset
/// }
///
/// extension Action {
///     var tag: ActionTag {
///         switch self {
///         case .start: .start
///         case .stop: .stop
///         case .reset: .reset
///         }
///     }
/// }
/// ```
///
/// Because the generated name is always the host's plus `Tag`, this can be
/// attached to an enumeration at file scope.
///
/// Pass `by:` instead when the tag enumeration already exists because this
/// enumeration is nested inside it — see ``MirroredCases()``. In that mode no
/// peer is generated and `tag` returns the outer type.
///
/// - Parameters:
///   - by: An existing tag enumeration to return from `tag`, instead of
///     generating one.
///   - backing: A raw-value type for the generated tag enumeration, such as
///     `String.self` or `Int.self`.
@attached(peer, names: suffixed(Tag))
@attached(member, names: named(tag))
public macro CaseTag(
    by: Any.Type? = nil,
    backing: Any.Type? = nil
) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "CaseTagMacro"
)

/// Copies the case names of a nested `@CaseTag(by:)` enumeration onto the
/// enumeration this is attached to.
///
/// It is ``CaseTag(by:backing:)`` turned inside out. There, the tag
/// enumeration is generated off to the side; here it is the one you declare,
/// with the payload-carrying variants nested inside it — which is what you
/// want when the tag has to be a single top-level name, as when generating
/// bindings for another language.
///
/// ```swift
/// @MirroredCases public enum TooltipType {
///     @CaseTag(by: TooltipType.self) public enum Union {
///         case text(String)
///         case icon(Int)
///         case custom
///     }
/// }
/// ```
///
/// expands to:
///
/// ```swift
/// public enum TooltipType {
///     public enum Union {
///         case text(String)
///         case icon(Int)
///         case custom
///
///         public var tag: TooltipType { ... }
///     }
///
///     case text
///     case icon
///     case custom
/// }
/// ```
///
/// A raw backing type is supported by writing it on the host directly, as in
/// `enum TooltipType: String`.
@attached(member, names: arbitrary)
public macro MirroredCases() = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "MirroredCasesMacro"
)
