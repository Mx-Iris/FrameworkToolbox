import Foundation
import FrameworkToolbox

extension FrameworkToolbox where Base: NSSortDescriptor {
    /// Returns the sort descriptor with reversed sorting order.
    @inlinable
    public var reversed: Base {
        return base.reversedSortDescriptor as? Base ?? base
    }
}
