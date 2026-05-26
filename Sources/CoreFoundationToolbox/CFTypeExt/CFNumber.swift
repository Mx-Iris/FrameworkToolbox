import Foundation
import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFNumber> {

    public static let positiveInfinity = kCFNumberPositiveInfinity!
    public static let negativeInfinity = kCFNumberNegativeInfinity!
    public static let nan = kCFNumberNaN!

    @inlinable
    public var type: CFNumberType {
        CFNumberGetType(base)
    }

    @inlinable
    public var byteSize: CFIndex {
        CFNumberGetByteSize(base)
    }

    @inlinable
    public var isFloatType: Bool {
        CFNumberIsFloatType(base)
    }

    @inlinable
    public func value<Target: CFNumberRepresentable>() -> Target {
        Target._from(cfNumber: base).result
    }
}

// MARK: - CFNumberRepresentable

public protocol CFNumberRepresentable {
    static var cfNumberType: CFNumberType { get }
    static func _from(cfNumber: CFNumber) -> (result: Self, lossless: Bool)
}

extension CFNumberRepresentable where Self: BinaryInteger {
    public static func _from(cfNumber: CFNumber) -> (result: Self, lossless: Bool) {
        var result = Self.zero
        let lossless = withUnsafeMutablePointer(to: &result) { pointer in
            CFNumberGetValue(cfNumber, Self.cfNumberType, pointer)
        }
        return (result, lossless)
    }
}

extension CFNumberRepresentable where Self: FloatingPoint {
    public static func _from(cfNumber: CFNumber) -> (result: Self, lossless: Bool) {
        var result = Self.zero
        let lossless = withUnsafeMutablePointer(to: &result) { pointer in
            CFNumberGetValue(cfNumber, Self.cfNumberType, pointer)
        }
        return (result, lossless)
    }
}

// TODO: Linux: CFNumberType on Linux
#if canImport(Darwin)

extension Int8: CFNumberRepresentable {
    public static let cfNumberType = CFNumberType.sInt8Type
}

extension Int16: CFNumberRepresentable {
    public static let cfNumberType = CFNumberType.sInt16Type
}

extension Int32: CFNumberRepresentable {
    public static let cfNumberType = CFNumberType.sInt32Type
}

extension Int64: CFNumberRepresentable {
    public static let cfNumberType = CFNumberType.sInt64Type
}

extension NSInteger: CFNumberRepresentable {
    public static let cfNumberType = CFNumberType.nsIntegerType
}

extension Float32: CFNumberRepresentable {
    public static let cfNumberType = CFNumberType.float32Type
}

extension Float64: CFNumberRepresentable {
    public static let cfNumberType = CFNumberType.float64Type
}

#if canImport(CoreGraphics)

import CoreGraphics

extension CGFloat: CFNumberRepresentable {
    public static let cfNumberType = CFNumberType.cgFloatType
}

#endif // canImport(CoreGraphics)

#endif
