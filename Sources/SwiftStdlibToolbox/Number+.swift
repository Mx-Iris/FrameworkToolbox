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

extension FrameworkToolbox where Base: BinaryInteger {
    @inlinable
    public var string: String { .init(base) }

    @inlinable
    public var cgFloat: CGFloat { .init(base) }

    @inlinable
    public var float: Float { .init(base) }

    @inlinable
    public var double: Double { .init(base) }

    @inlinable
    public var int: Int { .init(base) }

    @inlinable
    public var uint: UInt { .init(base) }

    @inlinable
    public var int8: Int8 { .init(base) }

    @inlinable
    public var int16: Int16 { .init(base) }

    @inlinable
    public var int32: Int32 { .init(base) }

    @inlinable
    public var int64: Int64 { .init(base) }

    @inlinable
    public var uint8: UInt8 { .init(base) }

    @inlinable
    public var uint16: UInt16 { .init(base) }

    @inlinable
    public var uint32: UInt32 { .init(base) }

    @inlinable
    public var uint64: UInt64 { .init(base) }

    @inlinable
    public var cfString: CFString { string as CFString }

    @inlinable
    public var nsString: NSString { string as NSString }
}

extension FrameworkToolbox where Base: BinaryFloatingPoint {
    @inlinable
    public var string: String { "\(self)" }

    @inlinable
    public var cgFloat: CGFloat { .init(base) }

    @inlinable
    public var float: Float { .init(base) }

    @inlinable
    public var double: Double { .init(base) }

    @inlinable
    public var int: Int { .init(base) }

    @inlinable
    public var uint: UInt { .init(base) }

    @inlinable
    public var int8: Int8 { .init(base) }

    @inlinable
    public var int16: Int16 { .init(base) }

    @inlinable
    public var int32: Int32 { .init(base) }

    @inlinable
    public var int64: Int64 { .init(base) }

    @inlinable
    public var uint8: UInt8 { .init(base) }

    @inlinable
    public var uint16: UInt16 { .init(base) }

    @inlinable
    public var uint32: UInt32 { .init(base) }

    @inlinable
    public var uint64: UInt64 { .init(base) }

    @inlinable
    public var cfString: CFString { string as CFString }

    @inlinable
    public var nsString: NSString { string as NSString }
}
