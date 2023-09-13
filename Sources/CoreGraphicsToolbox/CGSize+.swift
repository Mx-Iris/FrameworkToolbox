#if canImport(CoreGraphics)

import CoreGraphics
import FrameworkToolbox

extension CGSize: FrameworkToolboxCompatible {}

public extension FrameworkToolbox where Base == CGSize {
    static var max: CGSize {
        .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
}

#endif
