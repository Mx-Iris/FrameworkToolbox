import Foundation
import FrameworkToolboxMacro

extension Bool: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
extension URL: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
extension Date: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
extension AnyKeyPath: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
extension String: FrameworkToolboxDynamicMemberLookup {}
extension Array: FrameworkToolboxDynamicMemberLookup {}
extension Dictionary: FrameworkToolboxDynamicMemberLookup {}
extension Set: FrameworkToolboxDynamicMemberLookup {}
extension Data: FrameworkToolboxDynamicMemberLookup {}
extension Substring: FrameworkToolboxDynamicMemberLookup {}


extension Int: FrameworkToolboxDynamicMemberLookup {}
extension Int8: FrameworkToolboxDynamicMemberLookup {}
extension Int16: FrameworkToolboxDynamicMemberLookup {}
extension Int32: FrameworkToolboxDynamicMemberLookup {}
extension Int64: FrameworkToolboxDynamicMemberLookup {}
extension UInt: FrameworkToolboxDynamicMemberLookup {}
extension UInt8: FrameworkToolboxDynamicMemberLookup {}
extension UInt16: FrameworkToolboxDynamicMemberLookup {}
extension UInt32: FrameworkToolboxDynamicMemberLookup {}
extension UInt64: FrameworkToolboxDynamicMemberLookup {}
extension Float: FrameworkToolboxDynamicMemberLookup {}
extension Double: FrameworkToolboxDynamicMemberLookup {}


@FrameworkToolboxExtension
extension BinaryInteger {}

@FrameworkToolboxExtension
extension BinaryFloatingPoint {}

@FrameworkToolboxExtension
extension Sequence {}

@FrameworkToolboxExtension
extension Collection {}

@FrameworkToolboxExtension
extension Error {}
