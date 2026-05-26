import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFArray> {

    public static let empty: CFArray = FrameworkToolbox<CFArray>.create(values: nil, count: 0)

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        values: UnsafeMutablePointer<UnsafeRawPointer?>?,
        count: CFIndex,
        pCallBacks: UnsafePointer<CFArrayCallBacks>? = pCFTypeArrayCallBacks
    ) -> CFArray {
        CFArrayCreate(allocator, values, count, pCallBacks)
    }

    @inlinable
    public func copy(allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default) -> CFArray {
        CFArrayCreateCopy(allocator, base)
    }

    @inlinable
    public func mutableCopy(allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default, capacity: CFIndex = 0) -> CFMutableArray {
        CFArrayCreateMutableCopy(allocator, capacity, base)
    }

    @inlinable
    public var count: CFIndex {
        CFArrayGetCount(base)
    }

    @inlinable
    public var fullRange: CFRange {
        CFRange(location: 0, length: count)
    }

    @inlinable
    public func count(of value: CFTypeRef) -> CFIndex {
        count(of: value, in: fullRange)
    }

    @inlinable
    public func count(of value: CFTypeRef, in range: CFRange) -> CFIndex {
        CFArrayGetCountOfValue(base, range, .fromCF(value))
    }

    @inlinable
    public func contains(_ value: CFTypeRef, in range: CFRange? = nil) -> Bool {
        CFArrayContainsValue(base, range ?? fullRange, .fromCF(value))
    }

    @inlinable
    public func value(at index: CFIndex) -> CFTypeRef {
        rawValue(at: index).asCF()
    }

    @inlinable
    public func rawValue(at index: CFIndex) -> UnsafeRawPointer {
        CFArrayGetValueAtIndex(base, index)!
    }

    @inlinable
    public func values(in range: CFRange) -> [CFTypeRef] {
        guard range.length > 0 else { return [] }
        return Array(unsafeUninitializedCapacity: range.length) { pointer, count in
            CFArrayGetValues(base, range, UnsafeMutablePointer(OpaquePointer(pointer.baseAddress)))
            count = range.length
        }
    }
}

extension CFArray: @retroactive RandomAccessCollection {

    @inlinable public var startIndex: Int { 0 }

    @inlinable public var endIndex: Int { box.count }

    @inlinable public subscript(position: Int) -> CFTypeRef { box.value(at: position) }
}

// MARK: - CFMutableArray

extension FrameworkToolbox<CFMutableArray> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        capacity: CFIndex = 0,
        pCallBacks: UnsafePointer<CFArrayCallBacks>? = pCFTypeArrayCallBacks
    ) -> CFMutableArray {
        CFArrayCreateMutable(allocator, capacity, pCallBacks)
    }

    @inlinable
    public func append(_ value: CFTypeRef) {
        append(rawValue: .fromCF(value))
    }

    @inlinable
    public func append(rawValue: UnsafeRawPointer) {
        CFArrayAppendValue(base, rawValue)
    }

    @inlinable
    public func append(contentsOf array: CFArray, range: CFRange? = nil) {
        CFArrayAppendArray(base, array, range ?? array.box.fullRange)
    }

    @inlinable
    public func insert(_ value: CFTypeRef, at index: CFIndex) {
        insert(rawValue: .fromCF(value), at: index)
    }

    @inlinable
    public func insert(rawValue: UnsafeRawPointer, at index: CFIndex) {
        CFArrayInsertValueAtIndex(base, index, rawValue)
    }

    @inlinable
    public func set(_ value: CFTypeRef, at index: CFIndex) {
        set(rawValue: .fromCF(value), at: index)
    }

    @inlinable
    public func set(rawValue: UnsafeRawPointer, at index: CFIndex) {
        CFArraySetValueAtIndex(base, index, rawValue)
    }

    @inlinable
    public func remove(at index: CFIndex) {
        CFArrayRemoveValueAtIndex(base, index)
    }

    @inlinable
    public func removeAll() {
        CFArrayRemoveAllValues(base)
    }

    @inlinable
    public func replace(range: CFRange, values: [CFTypeRef]) {
        values.withUnsafeBufferPointer { pointer in
            CFArrayReplaceValues(base, range, UnsafeMutablePointer(OpaquePointer(pointer.baseAddress)), values.count)
        }
    }

    @inlinable
    public func swapAt(_ i: CFIndex, _ j: CFIndex) {
        CFArrayExchangeValuesAtIndices(base, i, j)
    }
}
