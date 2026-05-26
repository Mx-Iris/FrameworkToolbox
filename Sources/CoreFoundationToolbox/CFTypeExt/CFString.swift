import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFString> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        cString: UnsafePointer<Int8>?,
        encoding: CFStringEncoding
    ) -> CFString {
        CFStringCreateWithCString(allocator, cString, encoding)
    }

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        bytes: UnsafePointer<UInt8>?,
        length: CFIndex,
        encoding: CFStringEncoding,
        isExternalRepresentation: Bool = false
    ) -> CFString {
        CFStringCreateWithBytes(allocator, bytes, length, encoding, isExternalRepresentation)
    }

    @inlinable
    public static func createNoCopy(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        cString: UnsafePointer<Int8>?,
        encoding: CFStringEncoding,
        contentsDeallocator: CFAllocator
    ) -> CFString {
        CFStringCreateWithCStringNoCopy(allocator, cString, encoding, contentsDeallocator)
    }

    @inlinable
    public static func createNoCopy(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        bytes: UnsafePointer<UInt8>?,
        length: CFIndex,
        encoding: CFStringEncoding,
        isExternalRepresentation: Bool = false,
        contentsDeallocator: CFAllocator
    ) -> CFString {
        CFStringCreateWithBytesNoCopy(allocator, bytes, length, encoding, isExternalRepresentation, contentsDeallocator)
    }

    @inlinable
    public func copy(allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default) -> CFString {
        CFStringCreateCopy(allocator, base)
    }

    @inlinable
    public func mutableCopy(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        capacity: CFIndex = 0
    ) -> CFMutableString {
        CFStringCreateMutableCopy(allocator, capacity, base)
    }

    @inlinable
    public var length: CFIndex {
        CFStringGetLength(base)
    }

    @inlinable
    public var fullRange: CFRange {
        CFRange(location: 0, length: length)
    }

    /// This function either returns the requested pointer immediately, with no memory allocations and no copying, in constant time, or returns NULL.
    @inlinable
    public func cStringPtr(encoding: CFStringEncoding) -> UnsafePointer<Int8>? {
        CFStringGetCStringPtr(base, encoding)
    }

    @inlinable
    public func substring(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        range: CFRange
    ) -> CFString {
        CFStringCreateWithSubstring(allocator, base, range)
    }

    @inlinable
    public var smallestEncoding: CFStringEncoding {
        CFStringGetSmallestEncoding(base)
    }

    @inlinable
    public var fastestEncoding: CFStringEncoding {
        CFStringGetFastestEncoding(base)
    }

    @inlinable
    public static var systemEncoding: CFStringEncoding {
        CFStringGetSystemEncoding()
    }
}

#if canImport(Carbon)

import Carbon

extension FrameworkToolbox<CFString> {

    @inlinable
    public static var applicationEncoding: CFStringEncoding {
        GetApplicationTextEncoding()
    }
}

#endif

// MARK: - CFMutableString

extension FrameworkToolbox<CFMutableString> {

    /// Perform in-place transliteration on a mutable string.
    ///
    /// The transformation represented by transform is applied to the given
    /// range of string, modifying it in place. Only the specified range is
    /// modified, but the transform may look at portions of the string outside
    /// that range for context. Reasons that the transform may be unsuccessful
    /// include an invalid transform identifier, and attempting to reverse an
    /// irreversible transform.
    ///
    /// - Parameters:
    ///   - transform: The transformation to apply.
    ///   - range: The range over which the transformation is applied. `nil`
    ///   causes the whole string to be transformed.
    ///   - reverse: A Boolean that, if true, specifies that the inverse
    ///   transform should be used (if it exists).
    /// - Returns: The new range corresponding to the original range. Or nil if
    /// unsuccessful.
    @inlinable
    public func transform(_ transform: CFString.Transform, range: CFRange? = nil, reverse: Bool = false) -> CFRange? {
        var range = range ?? CFRange(location: 0, length: CFStringGetLength(base))
        guard CFStringTransform(base, &range, transform.rawValue, reverse) else {
            return nil
        }
        return range
    }
}
