import Foundation
import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFRange> {

    public static let zero = CFRange(location: 0, length: 0)

    @inlinable
    public var range: Range<Int> {
        base.location ..< (base.location + base.length)
    }
}
