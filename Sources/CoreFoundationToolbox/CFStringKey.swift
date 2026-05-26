import Foundation
import CoreFoundation
import FrameworkToolbox

public protocol CFStringKey: RawRepresentable, ReferenceConvertible, ExpressibleByStringLiteral, _CFConvertible where RawValue == CFString, ReferenceType == NSString, _CFType == CFString {
    init(_ key: CFString)
}

extension CFStringKey {

    public init(rawValue: CFString) {
        self.init(rawValue)
    }

    public init(stringLiteral value: String) {
        self.init(CFString.box.from(value))
    }

    public var description: String {
        String._bridgeFromCF(rawValue)
    }

    public var debugDescription: String {
        description
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.box.cfEqual(to: rhs.rawValue)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.box.cfHash)
    }

    public func _bridgeToObjectiveC() -> NSString {
        rawValue._bridgeToNS()
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSString, result: inout Self?) {
        result = Self(CFString._bridgeFromNS(source))
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSString, result: inout Self?) -> Bool {
        _forceBridgeFromObjectiveC(source, result: &result)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> Self {
        var result: Self?
        _forceBridgeFromObjectiveC(source!, result: &result)
        return result!
    }

    public func _bridgeToCF() -> CFString {
        rawValue
    }

    public static func _bridgeFromCF(_ source: CFString) -> Self {
        self.init(source)
    }
}
