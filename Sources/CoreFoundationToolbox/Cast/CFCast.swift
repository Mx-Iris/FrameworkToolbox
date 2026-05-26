import CoreFoundation
import FrameworkToolbox

@inlinable public func cfCast<Source, Target: CFType>(_ source: Source, to type: Target.Type = Target.self) -> Target? {
    // TODO: Cast to _CFTollFreeBridgingMutableType
    // if let t = T.self as? _CFTollFreeBridgingNSType.Type {
    //     return type(of: v) as? t.bridgedNSType
    // }
    // if Target.self is _CFMutableType.Type {
    //     assertionFailure("Cast '\(v)' to CoreFoundation mutable type '\(type)' is not supported and will always produce nil.")
    //     return nil
    // }
    let ref = source as CFTypeRef
    if CFGetTypeID(ref) == type.typeID {
        return (ref as! Target)
    } else {
        return nil
    }
}

@inlinable public func cfCast<Source, Target: _CFTollFreeBridgeable>(_ source: Source, to type: Target.Type = Target.self) -> Target? {
    if let nsValue = source as? Target.BridgedNSType {
        return (nsValue as! Target)
    } else {
        return nil
    }
}

@inlinable public func cfUnwrap(_ value: CFTypeRef) -> CFTypeRef? {
    kCFNull.box.cfEqual(to: value) ? nil : value
}

// MARK: - Box namespace

extension FrameworkToolbox where Base: CFType {
    @inlinable
    public static func cast<Source>(_ source: Source) -> Base? {
        cfCast(source, to: Base.self)
    }
}

extension FrameworkToolbox where Base: _CFTollFreeBridgeable {
    @inlinable
    public static func cast<Source>(_ source: Source) -> Base? {
        cfCast(source, to: Base.self)
    }
}
