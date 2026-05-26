import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFAllocator> {

    public static let systemDefault = kCFAllocatorSystemDefault!
    public static let malloc = kCFAllocatorMalloc!
    public static let mallocZone = kCFAllocatorMallocZone!
    public static let null = kCFAllocatorNull!
    public static let useContext = kCFAllocatorUseContext!

    @inlinable
    public static var `default`: CFAllocator {
        get { CFAllocatorGetDefault().takeUnretainedValue() }
        set { CFAllocatorSetDefault(newValue) }
    }

    /// Set an allocator as the default in a nested fashion.
    @inlinable
    public func withDefaultAllocator(do body: () throws -> Void) rethrows {
        let previous = FrameworkToolbox<CFAllocator>.default
        FrameworkToolbox<CFAllocator>.default = base
        defer { FrameworkToolbox<CFAllocator>.default = previous }
        try body()
    }

    @inlinable
    public var context: CFAllocatorContext {
        var context = CFAllocatorContext()
        CFAllocatorGetContext(base, &context)
        return context
    }

    @inlinable
    public func allocate(size: CFIndex) -> UnsafeMutableRawPointer {
        CFAllocatorAllocate(base, size, 0)
    }

    @inlinable
    public func reallocate(_ pointer: UnsafeMutableRawPointer, newSize: CFIndex) -> UnsafeMutableRawPointer {
        CFAllocatorReallocate(base, pointer, newSize, 0)
    }

    @inlinable
    public func deallocate(_ pointer: UnsafeMutableRawPointer) {
        CFAllocatorDeallocate(base, pointer)
    }

    @inlinable
    public func preferredSize(for size: CFIndex) -> CFIndex {
        CFAllocatorGetPreferredSizeForSize(base, size, 0)
    }
}
