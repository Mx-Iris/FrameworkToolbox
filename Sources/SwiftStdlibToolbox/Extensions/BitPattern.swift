import FrameworkToolbox

public struct BitPattern<Base> {
    public var base: Base

    public init(_ base: Base) {
        self.base = base
    }
}

public protocol BitPatternCompatible<Base> {
    associatedtype Base
    var bitPattern: BitPattern<Base> { set get }
    static var bitPattern: BitPattern<Base>.Type { set get }
}

extension BitPatternCompatible {
    public var bitPattern: BitPattern<Self> {
        set {}
        get { BitPattern(self) }
    }

    public static var bitPattern: BitPattern<Self>.Type {
        set {}
        get { BitPattern<Self>.self }
    }
}

extension FrameworkToolbox: BitPatternCompatible {
    public var bitPattern: BitPattern<Base> {
        set {}
        get { BitPattern(base) }
    }

    public static var bitPattern: BitPattern<Base>.Type {
        set {}
        get { BitPattern<Base>.self }
    }
}

extension BitPattern<UInt> {
    @inlinable
    public var int: Int {
        .init(bitPattern: base)
    }
}

extension BitPattern<Int> {
    @inlinable
    public var uint: UInt {
        .init(bitPattern: base)
    }
}

extension BitPattern<UInt64> {
    @inlinable
    public var int64: Int64 {
        .init(bitPattern: base)
    }

    @inlinable
    public var double: Double {
        .init(bitPattern: base)
    }
}

extension BitPattern<Int64> {
    @inlinable
    public var uint64: UInt64 {
        .init(bitPattern: base)
    }
}

extension BitPattern<UInt32> {
    @inlinable
    public var int32: Int32 {
        .init(bitPattern: base)
    }
}

extension BitPattern<Int32> {
    @inlinable
    public var uint32: UInt32 {
        .init(bitPattern: base)
    }
}

extension BitPattern<UInt16> {
    @inlinable
    public var int16: Int16 {
        .init(bitPattern: base)
    }
}

extension BitPattern<Int16> {
    @inlinable
    public var uint16: UInt16 {
        .init(bitPattern: base)
    }
}

extension BitPattern<UInt8> {
    @inlinable
    public var int8: Int8 {
        .init(bitPattern: base)
    }
}

extension BitPattern<Int8> {
    @inlinable
    public var uint8: UInt8 {
        .init(bitPattern: base)
    }
}

extension BitPattern<String> {
    @inlinable
    public var binaryStringAsDouble: Double? {
        guard let bitPattern = UInt64(base, radix: 2) else { return nil }
        return Double(bitPattern: bitPattern)
    }

    @inlinable
    public var hexStringAsDouble: Double? {
        guard let bitPattern = UInt64(base, radix: 16) else { return nil }
        return Double(bitPattern: bitPattern)
    }

    @inlinable
    public var binaryStringAsFloat: Float? {
        guard let bitPattern = UInt32(base, radix: 2) else { return nil }
        return Float(bitPattern: bitPattern)
    }

    @inlinable
    public var hexStringAsFloat: Float? {
        guard let bitPattern = UInt32(base, radix: 16) else { return nil }
        return Float(bitPattern: bitPattern)
    }

    #if arch(arm64)
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @inlinable
    public var binaryStringAsFloat16: Float16? {
        guard let bitPattern = UInt16(base, radix: 2) else { return nil }
        return Float16(bitPattern: bitPattern)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @inlinable
    public var hexStringAsFloat16: Float16? {
        guard let bitPattern = UInt16(base, radix: 16) else { return nil }
        return Float16(bitPattern: bitPattern)
    }
    #endif
}

#if arch(arm64)
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension BitPattern<Float16> {
    @inlinable
    public var binaryString: String {
        .init(base.bitPattern, radix: 2)
    }

    @inlinable
    public var hexString: String {
        .init(base.bitPattern, radix: 16)
    }
}
#endif

extension BitPattern<Float> {
    @inlinable
    public var binaryString: String {
        .init(base.bitPattern, radix: 2)
    }

    @inlinable
    public var hexString: String {
        .init(base.bitPattern, radix: 16)
    }
}

extension BitPattern<Double> {
    @inlinable
    public var binaryString: String {
        .init(base.bitPattern, radix: 2)
    }

    @inlinable
    public var hexString: String {
        .init(base.bitPattern, radix: 16)
    }
}

extension String: BitPatternCompatible {}

extension Float: BitPatternCompatible {}
extension Double: BitPatternCompatible {}
#if arch(arm64)
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension Float16: BitPatternCompatible {}
#endif

extension UInt: BitPatternCompatible {}
extension UInt64: BitPatternCompatible {}
extension UInt32: BitPatternCompatible {}
extension UInt16: BitPatternCompatible {}
extension UInt8: BitPatternCompatible {}

extension Int: BitPatternCompatible {}
extension Int64: BitPatternCompatible {}
extension Int32: BitPatternCompatible {}
extension Int16: BitPatternCompatible {}
extension Int8: BitPatternCompatible {}
