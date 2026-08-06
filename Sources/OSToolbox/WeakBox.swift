/// A generic weak reference container for thread-safe weak properties.
///
/// Lock types such as ``Mutex`` and `OSAllocatedUnfairLock` hold their state
/// inline, which a `weak` binding cannot be. Boxing the reference gives the
/// lock something concrete to own while leaving the referent unretained, which
/// is what `@Mutex weak var` and `@OSAllocatedUnfairLock weak var` expand to.
public struct WeakBox<Object: AnyObject> {
    public weak var value: Object?

    public init(_ value: Object? = nil) {
        self.value = value
    }
}

extension WeakBox: Sendable where Object: Sendable {}
