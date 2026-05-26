import CoreFoundation

extension UnsafeRawPointer {

    @inlinable
    func asCF() -> CFTypeRef {
        Unmanaged<CFTypeRef>.fromOpaque(self).takeUnretainedValue()
    }

    @inlinable
    static func fromCF(_ value: CFTypeRef) -> UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(value).toOpaque())
    }
}

@inline(__always)
private func _persistedPointer<T>(to value: T) -> UnsafePointer<T> {
    let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    pointer.initialize(to: value)
    return UnsafePointer(pointer)
}

public let pCFTypeArrayCallBacks: UnsafePointer<CFArrayCallBacks> = _persistedPointer(to: kCFTypeArrayCallBacks)
public let pCFTypeDictionaryKeyCallBacks: UnsafePointer<CFDictionaryKeyCallBacks> = _persistedPointer(to: kCFTypeDictionaryKeyCallBacks)
public let pCFTypeDictionaryValueCallBacks: UnsafePointer<CFDictionaryValueCallBacks> = _persistedPointer(to: kCFTypeDictionaryValueCallBacks)
