import FrameworkToolbox

extension FrameworkToolbox where Base: OptionalProtocol {
    @inlinable public func asyncMap<E, U>(_ transform: (Base.Wrapped) async throws(E) -> U) async throws(E) -> U? where E: Swift.Error, U: ~Copyable {
        switch base.flatMap({ $0 }) {
        case .none:
            return nil
        case .some(let wrapped):
            return try await transform(wrapped)
        }
    }
}

extension FrameworkToolbox where Base: Sequence {
    @inlinable public func asyncMap<T, E>(_ transform: (Base.Element) async throws(E) -> T) async throws(E) -> [T] where E: Swift.Error {
        var results: [T] = []
        for element in base {
            try await results.append(transform(element))
        }
        return results
    }
}
