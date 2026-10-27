#if canImport(ObjectiveC)
import Foundation

/// A type whose Objective-C type encoding the runtime macros cannot work out on
/// their own, and that supplies it instead.
///
/// The macros derive encodings for the standard scalars, object types,
/// `RawRepresentable` enumerations and option sets, and the common Core
/// Graphics structs. A struct outside that set — `CATransform3D`, say — has to
/// say what it is:
///
/// ```swift
/// extension CATransform3D: ObjCTypeEncodable {
///     public static var objCTypeEncoding: String { "{CATransform3D=dddddddddddddddd}" }
/// }
/// ```
///
/// Frame offsets are not part of the comparison, so none are needed.
public protocol ObjCTypeEncodable {
    static var objCTypeEncoding: String { get }
}

/// Objective-C type encodings worked out by the compiler, for the code the
/// runtime macros generate.
///
/// A macro only sees a type's spelling, and `TimeInterval`, `NSInteger`,
/// `pid_t` or `NSTextAlignment` say nothing about what they encode as. The
/// macros look the common spellings up in a table of their own and, for any
/// other, generate `_ObjCTypeEncoding.of(T.self)`: overload resolution at that
/// call site sees through typealiases and picks by what the type is, the way
/// the macro cannot. Concrete overloads beat the generic ones, so `Int` — which
/// is also `_ObjectiveCBridgeable` — still encodes as `q` and not `@`.
///
/// Not meant to be called by hand.
@_documentation(visibility: private)
public enum _ObjCTypeEncoding {
    /// A method encoding assembled from its parts: return type, `@:` for the
    /// receiver and selector, then each parameter.
    @inlinable
    public static func method(_ components: [String]) -> String {
        components.joined()
    }

    // MARK: Scalars

    @inlinable public static func of(_: Void.Type) -> String { "v" }
    @inlinable public static func of(_: Bool.Type) -> String { "B" }
    @inlinable public static func of(_: Int.Type) -> String { "q" }
    @inlinable public static func of(_: UInt.Type) -> String { "Q" }
    @inlinable public static func of(_: Int8.Type) -> String { "c" }
    @inlinable public static func of(_: UInt8.Type) -> String { "C" }
    @inlinable public static func of(_: Int16.Type) -> String { "s" }
    @inlinable public static func of(_: UInt16.Type) -> String { "S" }
    @inlinable public static func of(_: Int32.Type) -> String { "i" }
    @inlinable public static func of(_: UInt32.Type) -> String { "I" }
    @inlinable public static func of(_: Int64.Type) -> String { "q" }
    @inlinable public static func of(_: UInt64.Type) -> String { "Q" }
    @inlinable public static func of(_: Float.Type) -> String { "f" }
    @inlinable public static func of(_: Double.Type) -> String { "d" }
    @inlinable public static func of(_: CGFloat.Type) -> String { "d" }

    // MARK: Runtime references and pointers

    @inlinable public static func of(_: Selector.Type) -> String { ":" }
    @inlinable public static func of(_: AnyClass.Type) -> String { "#" }
    @inlinable public static func of(_: UnsafeRawPointer.Type) -> String { "^v" }
    @inlinable public static func of(_: UnsafeMutableRawPointer.Type) -> String { "^v" }
    @inlinable public static func of(_: OpaquePointer.Type) -> String { "^v" }
    @inlinable public static func of<Pointee>(_: UnsafePointer<Pointee>.Type) -> String { "^v" }
    @inlinable public static func of<Pointee>(_: UnsafeMutablePointer<Pointee>.Type) -> String { "^v" }

    // MARK: Structs

    @inlinable public static func of(_: CGPoint.Type) -> String { "{CGPoint=dd}" }
    @inlinable public static func of(_: CGSize.Type) -> String { "{CGSize=dd}" }
    @inlinable public static func of(_: CGVector.Type) -> String { "{CGVector=dd}" }
    @inlinable public static func of(_: CGRect.Type) -> String { "{CGRect={CGPoint=dd}{CGSize=dd}}" }
    @inlinable public static func of(_: CGAffineTransform.Type) -> String { "{CGAffineTransform=dddddd}" }
    @inlinable public static func of(_: NSRange.Type) -> String { "{_NSRange=QQ}" }
    #if os(macOS)
    @inlinable public static func of(_: NSEdgeInsets.Type) -> String { "{NSEdgeInsets=dddd}" }
    #endif

    // MARK: By what the type is
    //
    // These are disfavored so that a type conforming to `ObjCTypeEncodable` gets
    // the encoding it states even when it also matches one of them, and the
    // fallback is disfavored too so that, among these, the most constrained one
    // still wins. Overlaps between two of them get an overload of their own.

    /// Any class, and any class-bound existential.
    @_disfavoredOverload
    @inlinable public static func of<Value: AnyObject>(_: Value.Type) -> String { "@" }

    /// A Swift value type that crosses as an object: `String`, `URL`, `Data`,
    /// the collections.
    @_disfavoredOverload
    @inlinable public static func of<Value: _ObjectiveCBridgeable>(_: Value.Type) -> String { "@" }

    @_disfavoredOverload
    @inlinable public static func of<Value: AnyObject & _ObjectiveCBridgeable>(_: Value.Type) -> String { "@" }

    /// An imported `NS_ENUM` or `NS_OPTIONS`, or an `@objc enum`: encoded as
    /// its raw value, which is what crosses.
    @_disfavoredOverload
    @inlinable public static func of<Value: RawRepresentable>(_: Value.Type) -> String {
        scalarEncoding(of: Value.RawValue.self) ?? "?"
    }

    /// A raw-value wrapper that also bridges: an `NS_TYPED_ENUM` such as
    /// `NSNotification.Name` crosses as its `NSString`, an integer-backed one
    /// such as `NSApplication.ModalResponse` as its integer.
    @_disfavoredOverload
    @inlinable public static func of<Value: RawRepresentable & _ObjectiveCBridgeable>(_: Value.Type) -> String {
        scalarEncoding(of: Value.RawValue.self) ?? "@"
    }

    /// A type that states its own encoding.
    @inlinable public static func of<Value: ObjCTypeEncodable>(_: Value.Type) -> String {
        Value.objCTypeEncoding
    }

    /// Anything else. Resolving here means the method using the type will fail
    /// its run-time comparison, so the call site is told now.
    @_disfavoredOverload
    @available(*, deprecated, message: "ObjCRuntimeToolbox cannot derive the Objective-C type encoding of this type, so a method using it fails validation at run time. Conform the type to ObjCTypeEncodable, or pass typeEncoding: to @RuntimeMethodReplacement.")
    public static func of<Value>(_: Value.Type) -> String { "?" }

    /// The encoding of a raw value type, or `nil` for one that is not a scalar.
    /// A run-time comparison because inside a generic function the raw value's
    /// type is a parameter, and overload resolution would only ever see that.
    @usableFromInline
    static func scalarEncoding(of type: Any.Type) -> String? {
        let scalarEncodings: [(Any.Type, String)] = [
            (Bool.self, "B"), (Int.self, "q"), (UInt.self, "Q"),
            (Int8.self, "c"), (UInt8.self, "C"), (Int16.self, "s"), (UInt16.self, "S"),
            (Int32.self, "i"), (UInt32.self, "I"), (Int64.self, "q"), (UInt64.self, "Q"),
            (Float.self, "f"), (Double.self, "d"), (CGFloat.self, "d"),
        ]
        return scalarEncodings.first { ObjectIdentifier($0.0) == ObjectIdentifier(type) }?.1
    }
}
#endif
