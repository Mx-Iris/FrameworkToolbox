import Foundation
import FrameworkToolbox

extension FrameworkToolbox where Base: BinaryFloatingPoint {
    @inlinable
    public var cfString: CFString { string as CFString }

    @inlinable
    public var nsString: NSString { string as NSString }
}

extension FrameworkToolbox where Base: BinaryInteger {
    @inlinable
    public var cfString: CFString { string as CFString }

    @inlinable
    public var nsString: NSString { string as NSString }
}
