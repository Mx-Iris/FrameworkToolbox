import Foundation
import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox where Base: CFType {

    @inlinable
    public static func from<Source: _CFConvertible>(_ source: Source) -> Base where Source._CFType == Base {
        source._bridgeToCF()
    }

    @inlinable
    public func asSwift<Target: _CFConvertible>() -> Target where Target._CFType == Base {
        Target._bridgeFromCF(base)
    }
}

extension FrameworkToolbox where Base: _CFTollFreeBridgeable {

    @inlinable
    public static func from(_ source: Base.BridgedNSType) -> Base {
        Base._bridgeFromNS(source)
    }

    @inlinable
    public func asNS() -> Base.BridgedNSType {
        base._bridgeToNS()
    }
}
