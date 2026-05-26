import Foundation
import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFAttributedString> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        string: CFString,
        attributes: [CFAttributedString.Key: Any] = [:]
    ) -> CFAttributedString {
        CFAttributedStringCreate(allocator, string, FrameworkToolbox<CFDictionary>.from(attributes))
    }

    @inlinable
    public func copy(allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default) -> CFAttributedString {
        CFAttributedStringCreateCopy(allocator, base)
    }

    @inlinable
    public func mutableCopy(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        capacity: CFIndex = 0
    ) -> CFMutableAttributedString {
        CFAttributedStringCreateMutableCopy(allocator, capacity, base)
    }

    @inlinable
    public var string: CFString {
        CFAttributedStringGetString(base)
    }

    @inlinable
    public var count: CFIndex {
        CFAttributedStringGetLength(base)
    }

    @inlinable
    public var fullRange: CFRange {
        CFRange(location: 0, length: count)
    }

    @inlinable
    public func attributes(at location: CFIndex) -> (attributes: [CFAttributedString.Key: Any], effectiveRange: CFRange) {
        var effectiveRange = CFRange()
        let attributes: [CFAttributedString.Key: Any] = CFAttributedStringGetAttributes(base, location, &effectiveRange)?.box.asSwift() ?? [:]
        return (attributes, effectiveRange)
    }

    @inlinable
    public func attribute(at location: CFIndex, name: CFAttributedString.Key) -> (attribute: CFTypeRef, effectiveRange: CFRange) {
        var effectiveRange = CFRange()
        let attribute = CFAttributedStringGetAttribute(base, location, name.rawValue, &effectiveRange)!
        return (attribute, effectiveRange)
    }
}
