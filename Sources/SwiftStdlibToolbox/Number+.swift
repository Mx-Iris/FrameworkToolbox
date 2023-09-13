import Foundation
import CoreGraphics
import FrameworkToolbox

extension Int: FrameworkToolboxCompatible {}
extension Int8: FrameworkToolboxCompatible {}
extension Int16: FrameworkToolboxCompatible {}
extension Int32: FrameworkToolboxCompatible {}
extension Int64: FrameworkToolboxCompatible {}
extension UInt: FrameworkToolboxCompatible {}
extension UInt8: FrameworkToolboxCompatible {}
extension UInt16: FrameworkToolboxCompatible {}
extension UInt32: FrameworkToolboxCompatible {}
extension UInt64: FrameworkToolboxCompatible {}
extension Float: FrameworkToolboxCompatible {}
extension Double: FrameworkToolboxCompatible {}

public extension FrameworkToolbox where Base: BinaryInteger {
    @inlinable
    var string: String { .init(base) }

    @inlinable
    var cgFloat: CGFloat { .init(base) }

    @inlinable
    var float: Float { .init(base) }

    @inlinable
    var double: Double { .init(base) }

    @inlinable
    var int: Int { .init(base) }

    @inlinable
    var uint: UInt { .init(base) }

    @inlinable
    var int8: Int8 { .init(base) }

    @inlinable
    var int16: Int16 { .init(base) }

    @inlinable
    var int32: Int32 { .init(base) }

    @inlinable
    var int64: Int64 { .init(base) }

    @inlinable
    var uint8: UInt8 { .init(base) }

    @inlinable
    var uint16: UInt16 { .init(base) }

    @inlinable
    var uint32: UInt32 { .init(base) }

    @inlinable
    var uint64: UInt64 { .init(base) }

    @inlinable
    var cfString: CFString { string as CFString }

    @inlinable
    var nsString: NSString { string as NSString }
}

public extension FrameworkToolbox where Base: BinaryFloatingPoint {
    @inlinable
    var string: String { "\(self)" }

    @inlinable
    var cgFloat: CGFloat { .init(base) }

    @inlinable
    var float: Float { .init(base) }

    @inlinable
    var double: Double { .init(base) }

    @inlinable
    var int: Int { .init(base) }

    @inlinable
    var uint: UInt { .init(base) }

    @inlinable
    var int8: Int8 { .init(base) }

    @inlinable
    var int16: Int16 { .init(base) }

    @inlinable
    var int32: Int32 { .init(base) }

    @inlinable
    var int64: Int64 { .init(base) }

    @inlinable
    var uint8: UInt8 { .init(base) }

    @inlinable
    var uint16: UInt16 { .init(base) }

    @inlinable
    var uint32: UInt32 { .init(base) }

    @inlinable
    var uint64: UInt64 { .init(base) }

    @inlinable
    var cfString: CFString { string as CFString }

    @inlinable
    var nsString: NSString { string as NSString }
}
