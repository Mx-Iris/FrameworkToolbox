#if canImport(os)

/// A macro that provides thread-safe access using Swift's Mutex.
///
/// When applied to a property:
/// ```swift
/// @Mutex
/// var counter: Int = 0
/// ```
///
/// The type annotation is optional when the property has an initial value —
/// `@Mutex var counter = 0` infers `Int` as an unannotated stored property
/// would. A `weak` property still needs its type.
///
/// When applied to a type:
/// ```swift
/// @Mutex
/// struct SharedState {
///     var counter: Int = 0
///     var message: String = ""
/// }
/// ```
@attached(peer, names: prefixed(_))
@attached(accessor)
// @attached(member, names: arbitrary)
public macro Mutex() = #externalMacro(
    module: "OSToolboxMacros",
    type: "MutexMacro"
)

#endif
