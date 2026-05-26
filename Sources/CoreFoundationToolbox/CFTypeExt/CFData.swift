import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFData> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        bytes: UnsafePointer<UInt8>?,
        length: CFIndex
    ) -> CFData {
        CFDataCreate(allocator, bytes, length)
    }

    @inlinable
    public static func createNoCopy(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        bytes: UnsafePointer<UInt8>?,
        length: CFIndex,
        bytesDeallocator: CFAllocator
    ) -> CFData {
        CFDataCreateWithBytesNoCopy(allocator, bytes, length, bytesDeallocator)
    }

    @inlinable
    public func copy(allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default) -> CFData {
        CFDataCreateCopy(allocator, base)
    }

    @inlinable
    public func mutableCopy(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        capacity: CFIndex = 0
    ) -> CFMutableData {
        CFDataCreateMutableCopy(allocator, capacity, base)
    }

    @inlinable
    public var length: CFIndex {
        CFDataGetLength(base)
    }

    @inlinable
    public var fullRange: CFRange {
        CFRange(location: 0, length: length)
    }

    @inlinable
    public var bytePtr: UnsafeBufferPointer<UInt8> {
        let pointer = CFDataGetBytePtr(base)
        return UnsafeBufferPointer(start: pointer, count: length)
    }

    @inlinable
    public func bytes(in range: CFRange) -> [UInt8] {
        guard range.length > 0 else { return [] }
        return Array(unsafeUninitializedCapacity: range.length) { pointer, count in
            CFDataGetBytes(base, range, pointer.baseAddress)
            count = range.length
        }
    }
}

extension CFData: @retroactive RandomAccessCollection {

    @inlinable public var startIndex: Int { 0 }

    @inlinable public var endIndex: Int { box.length }

    @inlinable public subscript(position: Int) -> UInt8 { box.bytePtr[position] }
}

// MARK: - CFMutableData

extension FrameworkToolbox<CFMutableData> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        capacity: CFIndex = 0
    ) -> CFMutableData {
        CFDataCreateMutable(allocator, capacity)
    }

    @inlinable
    public var mutableBytePtr: UnsafeMutableBufferPointer<UInt8> {
        let pointer = CFDataGetMutableBytePtr(base)
        return UnsafeMutableBufferPointer(start: pointer, count: CFDataGetLength(base))
    }

    @inlinable
    public func setLength(_ length: CFIndex) {
        CFDataSetLength(base, length)
    }

    @inlinable
    public func increaseLength(_ extraLength: CFIndex) {
        CFDataIncreaseLength(base, extraLength)
    }

    @inlinable
    public func append(bytes: UnsafePointer<UInt8>, length: CFIndex) {
        CFDataAppendBytes(base, bytes, length)
    }

    @inlinable
    public func replaceBytes(range: CFRange, newBytes: UnsafePointer<UInt8>, length: CFIndex) {
        CFDataReplaceBytes(base, range, newBytes, length)
    }

    @inlinable
    public func deleteBytes(range: CFRange) {
        CFDataDeleteBytes(base, range)
    }
}
