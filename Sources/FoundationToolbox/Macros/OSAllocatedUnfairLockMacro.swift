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
/// - Note: Available on macOS 13.0+, iOS 16.0+, tvOS 16.0+, watchOS 9.0+.
@attached(peer, names: prefixed(_))
@attached(accessor)
public macro OSAllocatedUnfairLock() = #externalMacro(
    module: "FoundationToolboxMacros",
    type: "OSAllocatedUnfairLockMacro"
)
