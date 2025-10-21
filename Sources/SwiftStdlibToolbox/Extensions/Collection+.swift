import FrameworkToolbox

extension FrameworkToolbox where Base: Collection, Base.Index == Int {
    public subscript(safe index: Base.Index) -> Base.Element? {
        guard index >= 0, index < base.count else { return nil }
        return base[index]
    }
}
