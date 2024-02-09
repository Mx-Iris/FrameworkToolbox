import Foundation
import FrameworkToolboxMacro

extension Bool: FrameworkToolboxCompatible {}
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
extension URL: FrameworkToolboxCompatible {}
extension Date: FrameworkToolboxCompatible {}

@FrameworkToolboxExtension
extension Sequence {}

@FrameworkToolboxExtension
extension Error {}
