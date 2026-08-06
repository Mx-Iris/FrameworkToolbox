#if canImport(Darwin) && _pointerBitWidth(_64)

import Darwin
import MachO

/// One replacement/replacee pair, laid out exactly like dyld's
/// `dyld_interpose_tuple` from `<mach-o/dyld_priv.h>`.
///
/// `@DyldDynamicInterpose` emits a tuple of two `@convention(c)` function
/// pointers into `__DATA,__dyn_interpose`; two pointer-sized fields in this
/// order is precisely that layout, which is what lets the registry reinterpret
/// the section's raw bytes as an array of these.
/// `@unchecked` because both fields are addresses of functions, which live for
/// as long as their image is mapped and are never written through.
public struct DyldDynamicInterposeTuple: @unchecked Sendable, Equatable {
    /// The function calls should be redirected to.
    public let replacement: UnsafeRawPointer

    /// The function being replaced.
    public let replacee: UnsafeRawPointer

    public init(replacement: UnsafeRawPointer, replacee: UnsafeRawPointer) {
        self.replacement = replacement
        self.replacee = replacee
    }
}

/// Reads the tuples `@DyldDynamicInterpose` planted in an image.
enum DyldDynamicInterposeRegistry {
    /// The segment/section `@DyldDynamicInterpose` writes into. Deliberately
    /// not dyld's `__DATA,__interpose`, so dyld leaves these tuples alone and
    /// the program controls when they take effect.
    static let segmentName = "__DATA"
    static let sectionName = "__dyn_interpose"

    static func registeredTuples(declaredIn declaringImage: UnsafeRawPointer) -> [DyldDynamicInterposeTuple] {
        let machHeader = declaringImage.assumingMemoryBound(to: mach_header_64.self)
        guard machHeader.pointee.magic == MH_MAGIC_64 else { return [] }

        var sectionSize: UInt = 0
        guard let sectionStart = getsectiondata(machHeader, segmentName, sectionName, &sectionSize) else {
            return []
        }

        let tupleStride = MemoryLayout<DyldDynamicInterposeTuple>.stride
        let tupleCount = Int(sectionSize) / tupleStride
        guard tupleCount > 0 else { return [] }

        let sectionBase = UnsafeRawPointer(sectionStart)
        var tuples: [DyldDynamicInterposeTuple] = []
        tuples.reserveCapacity(tupleCount)
        for tupleIndex in 0 ..< tupleCount {
            tuples.append(
                sectionBase.loadUnaligned(
                    fromByteOffset: tupleIndex * tupleStride,
                    as: DyldDynamicInterposeTuple.self
                )
            )
        }
        return tuples
    }
}

#endif
