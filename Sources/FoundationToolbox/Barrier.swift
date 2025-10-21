import Foundation

@propertyWrapper
public struct MainBarrier<Value>: @unchecked Sendable {
    private var _wrappedValue: Value

    public var wrappedValue: Value {
        set {
            sync {
                _wrappedValue = newValue
            }
        }
        get {
            sync {
                _wrappedValue
            }
        }
    }

    public init(wrappedValue: Value) {
        self._wrappedValue = wrappedValue
    }

    private func sync<T>(_ perform: () -> T) -> T {
        if Thread.isMainThread {
            return perform()
        } else {
            return DispatchQueue.main.sync {
                return perform()
            }
        }
    }
}

extension MainBarrier: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension MainBarrier: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

extension MainBarrier: Codable where Value: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(wrappedValue: Value(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

@propertyWrapper
public final class ConcurrentBarrier<Value>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.JH.BarrierPropertyWrapper", attributes: .concurrent)

    private var _wrappedValue: Value

    public init(wrappedValue: Value) {
        self._wrappedValue = wrappedValue
    }

    public var wrappedValue: Value {
        get {
            return queue.sync { _wrappedValue }
        }
        set {
            queue.async(flags: .barrier) {
                self._wrappedValue = newValue
            }
        }
    }

    public var projectedValue: ConcurrentBarrier<Value> {
        return self
    }

    public func get() -> Value {
        return queue.sync { _wrappedValue }
    }

    public func set(_ newValue: Value) {
        queue.sync(flags: .barrier) {
            self._wrappedValue = newValue
        }
    }

    public func set(_ newValue: Value, completion: @escaping () -> Void) {
        queue.async(flags: .barrier) {
            self._wrappedValue = newValue
            completion()
        }
    }

    public func mutate(_ mutation: @escaping (inout Value) -> Void) {
        queue.async(flags: .barrier) {
            mutation(&self._wrappedValue)
        }
    }

    public func mutateAndReturn<T>(_ mutation: @escaping (inout Value) -> T) -> T {
        return queue.sync(flags: .barrier) {
            mutation(&self._wrappedValue)
        }
    }
}

extension ConcurrentBarrier: Equatable where Value: Equatable {
    public static func == (lhs: ConcurrentBarrier, rhs: ConcurrentBarrier) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension ConcurrentBarrier: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

extension ConcurrentBarrier: Codable where Value: Codable {
    public convenience init(from decoder: any Decoder) throws {
        try self.init(wrappedValue: Value(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}
