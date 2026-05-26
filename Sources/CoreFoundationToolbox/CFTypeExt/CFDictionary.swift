import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFDictionary> {

    public static let empty = FrameworkToolbox<CFDictionary>.create(keys: nil, values: nil, count: 0)

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        keys: UnsafeMutablePointer<UnsafeRawPointer?>?,
        values: UnsafeMutablePointer<UnsafeRawPointer?>?,
        count: CFIndex,
        keyCallBacks: UnsafePointer<CFDictionaryKeyCallBacks>? = pCFTypeDictionaryKeyCallBacks,
        valueCallBacks: UnsafePointer<CFDictionaryValueCallBacks>? = pCFTypeDictionaryValueCallBacks
    ) -> CFDictionary {
        CFDictionaryCreate(allocator, keys, values, count, keyCallBacks, valueCallBacks)
    }

    @inlinable
    public func copy(allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default) -> CFDictionary {
        CFDictionaryCreateCopy(allocator, base)
    }

    @inlinable
    public func mutableCopy(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        capacity: CFIndex = 0
    ) -> CFMutableDictionary {
        CFDictionaryCreateMutableCopy(allocator, capacity, base)
    }

    @inlinable
    public var count: CFIndex {
        CFDictionaryGetCount(base)
    }

    @inlinable
    public func count(ofKey key: CFTypeRef) -> CFIndex {
        CFDictionaryGetCountOfKey(base, .fromCF(key))
    }

    @inlinable
    public func count(ofValue value: CFTypeRef) -> CFIndex {
        CFDictionaryGetCountOfValue(base, .fromCF(value))
    }

    @inlinable
    public func contains(key: CFTypeRef) -> Bool {
        CFDictionaryContainsValue(base, .fromCF(key))
    }

    @inlinable
    public func contains(value: CFTypeRef) -> Bool {
        CFDictionaryContainsValue(base, .fromCF(value))
    }

    @inlinable
    public func value(key: CFTypeRef) -> CFTypeRef? {
        rawValue(key: key)?.asCF()
    }

    @inlinable
    public func rawValue(key: CFTypeRef) -> UnsafeRawPointer? {
        CFDictionaryGetValue(base, .fromCF(key))
    }
}

extension FrameworkToolbox<CFMutableDictionary> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        capacity: CFIndex,
        keyCallBacks: UnsafePointer<CFDictionaryKeyCallBacks>? = pCFTypeDictionaryKeyCallBacks,
        valueCallBacks: UnsafePointer<CFDictionaryValueCallBacks>? = pCFTypeDictionaryValueCallBacks
    ) -> CFMutableDictionary {
        CFDictionaryCreateMutable(allocator, capacity, keyCallBacks, valueCallBacks)
    }

    @inlinable
    public func addValue(_ value: CFTypeRef, for key: CFTypeRef) {
        CFDictionaryAddValue(base, .fromCF(key), .fromCF(value))
    }

    @inlinable
    public func setValue(_ value: CFTypeRef, for key: CFTypeRef) {
        CFDictionarySetValue(base, .fromCF(key), .fromCF(value))
    }

    @inlinable
    public func replaceValue(_ value: CFTypeRef, for key: CFTypeRef) {
        CFDictionaryReplaceValue(base, .fromCF(key), .fromCF(value))
    }

    @inlinable
    public func removeValue(for key: CFTypeRef) {
        CFDictionaryRemoveValue(base, .fromCF(key))
    }

    @inlinable
    public func removeAllValues() {
        CFDictionaryRemoveAllValues(base)
    }
}
