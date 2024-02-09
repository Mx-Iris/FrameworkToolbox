import Foundation
import FrameworkToolboxMacro

extension Bool: FrameworkToolboxCompatible {}
extension URL: FrameworkToolboxCompatible {}
extension Date: FrameworkToolboxCompatible {}
extension AnyKeyPath: FrameworkToolboxCompatible {}

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
