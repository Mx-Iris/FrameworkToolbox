import FrameworkToolbox

extension FrameworkToolbox where Base: BinaryInteger {
    @inlinable
    public var string: String { .init(base) }

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
}

extension FrameworkToolbox where Base: BinaryFloatingPoint {
    @inlinable
    public var string: String { "\(self)" }

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
}
