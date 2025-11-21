import FrameworkToolbox

extension FrameworkToolbox where Base: Collection, Base.Index == Int {
    @inlinable public subscript(safe index: Base.Index) -> Base.Element? {
        get {
            guard index >= 0, index < base.count else { return nil }
            return base[index]
        }
    }
}

extension FrameworkToolbox where Base: MutableCollection, Base.Index == Int {
    @inlinable public subscript(safe index: Base.Index) -> Base.Element? {
        set {
            guard index >= 0, index < base.count, let newValue else { return }
            base[index] = newValue
        }
        get {
            guard index >= 0, index < base.count else { return nil }
            return base[index]
        }
    }
}
