//
//  Adapted from Dynamic by Mhd Hejazi (https://github.com/mhdhejazi/Dynamic),
//  distributed under the Apache License 2.0. See LICENSES/Dynamic-LICENSE.
//

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

// MARK: - Objects

extension DynamicObject {

    /// The resolved object, sending the pending message if needed.
    public var asAnyObject: AnyObject? { resolve() }

    public var asObject: NSObject? { asAnyObject as? NSObject }
    public var asArray: NSArray? { asAnyObject as? NSArray }
    public var asDictionary: NSDictionary? { asAnyObject as? NSDictionary }
    public var asString: String? { asAnyObject?.description }

    /// The result boxed as an `NSValue`.
    ///
    /// Objects are boxed non-retained; anything else is copied out of the
    /// invocation's return buffer along with its type encoding, which is what
    /// makes the typed accessors below possible for structs and primitives the
    /// compiler never saw a declaration for.
    public var asValue: NSValue? {
        if let resolvedObject = resolve() {
            return NSValue(nonretainedObject: resolvedObject)
        }

        guard let invocation, invocation.returnsValue, invocation.returnLength > 0 else {
            return nil
        }

        let (encodedSize, encodedAlignment) = invocation.returnTypeLayout

        return invocation.withReturnTypeCString { returnTypeCString in
            let byteCount = max(invocation.returnLength, encodedSize, 1)
            return withUnsafeTemporaryAllocation(
                byteCount: byteCount,
                alignment: max(encodedAlignment, 1)
            ) { buffer -> NSValue? in
                guard let baseAddress = buffer.baseAddress else { return nil }

                // `getReturnValue:` writes only as many bytes as the return type
                // occupies; zeroing first keeps any remaining padding defined.
                baseAddress.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
                invocation.getReturnValue(intoRawBuffer: baseAddress)

                return NSValue(bytes: baseAddress, objCType: returnTypeCString)
            }
        }
    }

    /// Reinterprets the result as `Unwrapped`, when the layouts agree.
    ///
    /// - Returns: `nil` when the method returned nothing, or when the size or
    ///   alignment of `Unwrapped` does not match the declared return type —
    ///   copying the bytes anyway would produce a plausible-looking wrong value.
    func unwrap<Unwrapped>() -> Unwrapped? {
        guard let value = asValue else { return nil }

        guard let invocation else {
            // Nothing was sent, so there is no return buffer to interpret; the
            // wrapper is standing in for an object it was handed directly.
            return object as? Unwrapped
        }

        // `^v` is `void *` and `@` is an object: both are already references, so
        // the box holds the pointer rather than a copy to reinterpret.
        let encoding = invocation.returnTypeEncoding
        if encoding == "^v" || encoding == "@" {
            return value.nonretainedObjectValue as? Unwrapped
        }

        let (encodedSize, encodedAlignment) = invocation.returnTypeLayout
        guard MemoryLayout<Unwrapped>.size == encodedSize,
              MemoryLayout<Unwrapped>.alignment == encodedAlignment else {
            return nil
        }

        return withUnsafeTemporaryAllocation(
            of: Unwrapped.self,
            capacity: 1
        ) { buffer -> Unwrapped? in
            guard let baseAddress = buffer.baseAddress else { return nil }
            value.getValue(baseAddress, size: encodedSize)
            return baseAddress.pointee
        }
    }

    /// Reinterprets the result as whatever type the call site expects.
    ///
    /// Use when the destination's type is known but writing it out would be
    /// redundant: `let version: OperatingSystemVersion? = value.asInferred()`.
    public func asInferred<Unwrapped>() -> Unwrapped? { unwrap() }
}

// MARK: - Primitives

extension DynamicObject {
    public var asInt8: Int8? { unwrap() }
    public var asUInt8: UInt8? { unwrap() }
    public var asInt16: Int16? { unwrap() }
    public var asUInt16: UInt16? { unwrap() }
    public var asInt32: Int32? { unwrap() }
    public var asUInt32: UInt32? { unwrap() }
    public var asInt64: Int64? { unwrap() }
    public var asUInt64: UInt64? { unwrap() }
    public var asFloat: Float? { unwrap() }
    public var asDouble: Double? { unwrap() }
    public var asBool: Bool? { unwrap() }
    public var asInt: Int? { unwrap() }
    public var asUInt: UInt? { unwrap() }
    public var asSelector: Selector? { unwrap() }
}

// MARK: - Core Graphics

// Upstream gated these on `canImport(UIKit)`, which left them missing on macOS
// even though Core Graphics defines the types on every platform.
#if canImport(CoreGraphics)
import CoreGraphics

extension DynamicObject {
    public var asCGPoint: CGPoint? { unwrap() }
    public var asCGVector: CGVector? { unwrap() }
    public var asCGSize: CGSize? { unwrap() }
    public var asCGRect: CGRect? { unwrap() }
    public var asCGAffineTransform: CGAffineTransform? { unwrap() }
}
#endif

// QuartzCore imports cleanly on watchOS but declares `CATransform3D` unavailable
// there, so `canImport` alone is not a sufficient guard — upstream's
// `!os(watchOS)` carries information `canImport` does not.
#if canImport(QuartzCore) && !os(watchOS)
import QuartzCore

extension DynamicObject {
    public var asCATransform3D: CATransform3D? { unwrap() }
}
#endif

// MARK: - Platform Geometry

#if canImport(UIKit)
import UIKit

extension DynamicObject {
    public var asUIEdgeInsets: UIEdgeInsets? { unwrap() }
    public var asUIOffset: UIOffset? { unwrap() }
}
#endif

// `os(macOS)`, not `canImport(AppKit)`: Mac Catalyst reports `canImport(AppKit)`
// as true while marking essentially all of AppKit `unavailable`, so that spelling
// compiles today only because `NSEdgeInsets` happens to be a plain Foundation
// struct — adding any real AppKit type here would break the Catalyst build.
// Catalyst callers get `asUIEdgeInsets` from the UIKit section above.
#if os(macOS)
import AppKit

extension DynamicObject {
    public var asNSEdgeInsets: NSEdgeInsets? { unwrap() }
}
#endif

#endif
