/// A generic weak reference container for thread-safe weak properties
public struct WeakBox<T: AnyObject> {
    public weak var value: T?

    public init(_ value: T? = nil) {
        self.value = value
    }
}
