import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox where Base: CFType {

    @inlinable
    public static var cfDescription: CFString {
        CFCopyTypeIDDescription(Base.typeID)
    }

    @inlinable
    public var cfDescription: CFString {
        CFCopyDescription(base)
    }

    @inlinable
    public func cfEqual(to other: CFTypeRef) -> Bool {
        CFEqual(base, other)
    }

    @inlinable
    public var cfHash: CFHashCode {
        CFHash(base)
    }

    #if canImport(Darwin)
    @inlinable
    public var cfRetainCount: CFIndex {
        CFGetRetainCount(base)
    }
    #endif

    @inlinable
    public var cfAllocator: CFAllocator {
        CFGetAllocator(base)
    }
}
