#if canImport(os)
/// A macro that provides thread-safe access using `OSAllocatedUnfairLock`.
///
/// When applied to a property:
/// ```swift
/// @OSAllocatedUnfairLock
/// var counter: Int = 0
/// ```
///
/// This generates a backing `OSAllocatedUnfairLock<Int>` storage property
/// and accessor methods that use `withLock` for thread-safe reads and writes.
///
/// The type annotation is optional when the property has an initial value —
/// `@OSAllocatedUnfairLock var counter = 0` infers `Int`. A `weak` property
/// still needs its type.
///
/// - Note: Available on macOS 13.0+, iOS 16.0+, tvOS 16.0+, watchOS 9.0+.
@available(SwiftStdlib 5.7, *)
@attached(peer, names: prefixed(_))
@attached(accessor)
public macro OSAllocatedUnfairLock() = #externalMacro(
    module: "OSToolboxMacros",
    type: "OSAllocatedUnfairLockMacro"
)

#endif
